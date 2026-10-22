"""Run AITUMeet: python run.py. Check credentials only: python run.py --check."""
import argparse
import logging
import signal
import sys
import threading
import time

from aitumeet.app import Bot, COMMANDS
from aitumeet.config import instance_lock, load_env
from aitumeet.storage import Database
from aitumeet.telegram import Telegram, TelegramError, deliver

LOG = logging.getLogger("aitumeet")


def main():
    parser = argparse.ArgumentParser(description="AITUMeet Telegram bot")
    parser.add_argument("--check",action="store_true",help="Read bot identity and webhook status; do not consume updates")
    parser.add_argument("--reset-webhook",action="store_true",help="Explicitly switch an existing webhook to polling, preserving pending updates")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO,format="%(asctime)s %(levelname)s %(message)s")
    token,path,admin = load_env()
    api = Telegram(token)
    identity = api.call("getMe")
    webhook = api.call("getWebhookInfo")
    LOG.info("Connected to @%s (id %s)",identity["username"],identity["id"])
    if args.check:
        LOG.info("Credential check passed. Webhook configured: %s. Pending updates: %s",bool(webhook.get("url")),webhook.get("pending_update_count",0))
        return
    if webhook.get("url") and not args.reset_webhook:
        raise RuntimeError("An existing webhook is configured. Use --reset-webhook only if you intend to switch this bot to polling.")
    if args.reset_webhook:
        api.call("deleteWebhook",drop_pending_updates=False)
    stop = threading.Event()
    def stop_handler(*_):
        stop.set()
    signal.signal(signal.SIGINT,stop_handler)
    if hasattr(signal,"SIGTERM"):
        signal.signal(signal.SIGTERM,stop_handler)
    with instance_lock(path):
        db = Database(path)
        stored_bot = db.meta("bot_id","")
        if stored_bot and stored_bot != str(identity["id"]):
            db.close()
            raise RuntimeError("This database belongs to a different bot. Set a new DATABASE_PATH.")
        with db.conn:
            db.set_meta("bot_id",identity["id"])
        bot = Bot(db,admin)
        try:
            api.call("setMyCommands",commands=COMMANDS)
            api.call("setMyDescription",description="AITUMeet — your campus, your people. Create a profile, meet students, and connect through mutual likes.")
            api.call("setMyShortDescription",short_description="Meet students. Find friends and study partners. Make new connections.")
        except TelegramError as error:
            if error.code == 401:
                raise
            LOG.warning("Could not update bot menu (%s); polling will still start",error.code)
        LOG.info("AITUMeet is running. Press Ctrl+C to stop. Database: %s",path)
        failures = 0
        try:
            while not stop.is_set():
                try:
                    deliver(db,api)
                    # Retry queued replies promptly instead of waiting an entire polling cycle.
                    waiting = db.conn.execute("SELECT 1 FROM outbox LIMIT 1").fetchone()
                    updates = api.call("getUpdates",offset=int(db.meta("offset")),timeout=2 if waiting else 20,allowed_updates=["message","callback_query"])
                    for update in updates:
                        if stop.is_set():
                            break
                        try:
                            bot.process_update(update)
                        except Exception as error:
                            # Do not log update contents (names, birth dates and contacts).
                            LOG.error("Update %s failed (%s)",update["update_id"],type(error).__name__)
                            # The transaction rolled back. Offer a recovery path and advance past a poison update.
                            with db.conn:
                                msg = update.get("message",update.get("callback_query",{}).get("message",{}))
                                chat = msg.get("chat",{})
                                if chat.get("type") == "private":
                                    bot.send(chat["id"],"Something went wrong. Your published profile is safe. Use /start to continue, or /cancel to leave the current action.")
                                db.set_meta("offset",update["update_id"]+1)
                        deliver(db,api)
                    failures = 0
                    with db.conn:
                        db.set_meta("heartbeat",int(time.time()))
                except TelegramError as error:
                    if error.code in (401,409):
                        raise
                    failures += 1
                    delay = max(error.retry_after,min(30,2 ** min(failures,5)))
                    LOG.warning("Telegram unavailable (%s). Reconnecting in %s seconds",error.code,delay)
                    stop.wait(delay)
        finally:
            db.close()
            LOG.info("AITUMeet stopped")


if __name__ == "__main__":
    try:
        main()
    except TelegramError as error:
        messages = {401:"Bot token was rejected. Update BOT_TOKEN.",409:"Another instance or webhook is consuming this bot's updates. Stop the other instance."}
        LOG.error(messages.get(error.code,f"Telegram connection failed (code {error.code}). Check your internet connection and try again."))
        sys.exit(1)
    except (ValueError,RuntimeError) as error:
        LOG.error("%s",error)
        sys.exit(1)

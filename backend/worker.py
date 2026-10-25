"""
LifeGuard 360 - Background Escalation Worker Daemon

Responsible for:
1. Periodically evaluating active check-in timers and escalating overdue check-ins.
2. Processing pending dispatches in the transactional outbox (SMS, Push).
3. Retrying failed dispatches according to exponential backoff.

Usage:
  python worker.py                 # Runs continuous background loop (default 10s interval)
  python worker.py --once          # Executes a single tick and exits (for cron jobs)
  python worker.py --interval 15   # Runs continuous loop with 15s interval
"""

import sys
import os
import time
import signal
import logging
import argparse
from datetime import datetime, timezone

from app import create_app
from app.extensions import db
from app.services.escalation_service import EscalationService

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] [Worker] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger('LifeGuardWorker')

_shutdown_requested = False


def _signal_handler(signum, frame):
    global _shutdown_requested
    logger.info(f"Signal {signum} received. Requesting clean worker shutdown...")
    _shutdown_requested = True


def run_tick(app):
    """Executes one evaluation and outbox processing tick inside application context."""
    with app.app_context():
        try:
            # 1. Evaluate overdue check-ins and trigger incidents
            escalated = EscalationService.check_and_escalate_overdue_checkins()
            if escalated:
                logger.warning(f"ESCALATION: {len(escalated)} overdue check-in(s) transitioned to ACTIVE incident.")

            # 2. Process outbox delivery for pending/retriable dispatches
            stats = EscalationService.process_pending_dispatches()
            if stats['processed'] > 0:
                logger.info(f"OUTBOX: Processed {stats['processed']} dispatches ({stats['sent']} sent, {stats['failed']} failed).")

            return {
                "escalated_count": len(escalated),
                "outbox_stats": stats,
                "timestamp": datetime.now(timezone.utc).isoformat()
            }
        except Exception as e:
            logger.error(f"Worker tick encountered exception: {e}", exc_info=True)
            try:
                db.session.rollback()
            except Exception:
                pass
            return None


def main():
    parser = argparse.ArgumentParser(description="LifeGuard 360 Escalation & Outbox Worker")
    parser.add_argument('--once', action='store_true', help="Run single tick and exit (for cron)")
    parser.add_argument('--interval', type=int, default=int(os.getenv('WORKER_POLL_INTERVAL', '10')), help="Polling interval in seconds (default: 10)")
    args = parser.parse_args()

    app = create_app(os.getenv('FLASK_ENV', 'development'))
    logger.info(f"Starting LifeGuard 360 Background Worker (Mode: {'Single-Tick' if args.once else f'Continuous, Interval: {args.interval}s'})...")

    if args.once:
        result = run_tick(app)
        logger.info(f"Single-tick completed. Result: {result}")
        sys.exit(0 if result is not None else 1)

    signal.signal(signal.SIGINT, _signal_handler)
    signal.signal(signal.SIGTERM, _signal_handler)

    while not _shutdown_requested:
        run_tick(app)
        # Sleep in small increments to respond quickly to signals
        for _ in range(args.interval * 2):
            if _shutdown_requested:
                break
            time.sleep(0.5)

    logger.info("Worker stopped cleanly.")


if __name__ == '__main__':
    main()

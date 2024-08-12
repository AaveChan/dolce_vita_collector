# ACI's Dolce Vita Collector

This project automates the process of minting to treasury for various Aave Pools across multiple networks. It includes a scheduled script that runs daily and weekly, with Telegram notifications for monitoring.

## Setup

1. Clone the repository:
   ```
   git clone https://github.com/yourusername/dolce_vita_collector.git
   cd dolce_vita_collector
   ```

2. Install Foundry if you haven't already:
   ```
   curl -L https://foundry.paradigm.xyz | bash
   foundryup
   ```

3. Copy `.env.example` to `.env` and fill in your private key and any other necessary details:
   ```
   cp .env.example .env
   ```

4. Build the project:
   ```
   forge build
   ```

5. Set up the automated script and Telegram notifications:
   - Ensure the `dolce_vita_collector_with_notifications.sh` script is in place and executable.
   - Set up systemd services and timers for daily and weekly runs (see "Automated Runs" section).
   - Configure the Telegram bot token and chat ID in the script.

## Usage

- To fetch reserves for all networks:
  ```
  make fetch-reserves
  ```

- To mint to treasury for a specific network and pool:
  ```
  make mint-to-treasury NETWORK=MAINNET POOL=MAIN
  ```

- The automated script runs daily (excluding MAINNET) and weekly (including MAINNET) at 8:00 AM UTC.

## Automated Runs

To set up automated runs, you need to create systemd service and timer files. Replace `/path/to/` with the actual path to your cloned repository.

1. Create service files:
   ```
   sudo nano /etc/systemd/system/dolce-vita-daily.service
   sudo nano /etc/systemd/system/dolce-vita-weekly.service
   ```

2. Create timer files:
   ```
   sudo nano /etc/systemd/system/dolce-vita-daily.timer
   sudo nano /etc/systemd/system/dolce-vita-weekly.timer
   ```

3. Enable and start the timers:
   ```
   sudo systemctl daemon-reload
   sudo systemctl enable dolce-vita-daily.timer dolce-vita-weekly.timer
   sudo systemctl start dolce-vita-daily.timer dolce-vita-weekly.timer
   ```

Refer to the provided service and timer file templates in the `systemd` directory and adjust paths as necessary.

## Monitoring

The script sends Telegram notifications for:
- Start of each run
- Successful completion of each run
- Any errors encountered during the run

To manually trigger a run:
```
/path/to/dolce_vita_collector/dolce_vita_collector_with_notifications.sh
```

Add `--include-mainnet` for a run that includes MAINNET.

## Logs

Logs are stored in `/var/log/dolce_vita_collector/`:
- `daily.log`: For daily runs
- `weekly.log`: For weekly runs (including MAINNET)

Ensure the log directory exists and is writable by the user running the script.

## Customization

When setting up this project, make sure to:
1. Update all paths in the scripts and service files to match your system's directory structure.
2. Configure your own Telegram bot token and chat ID in the notification script.
3. Adjust the systemd service files to use the correct user and group for your system.

## License

This project is licensed under the MIT License.
# ACI's Dolce Vita Collector

This project automates the process of minting to treasury for various Aave Pools across multiple networks. It includes scheduled scripts that run daily for L2 networks and weekly for MAINNET, with Telegram notifications for monitoring.

## Setup

1. Clone the repository:
   ```
   git clone
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
   - Ensure the `dolce_vita_collector_with_notifications.sh` script is executable:
     ```
     chmod +x dolce_vita_collector_with_notifications.sh
     ```
   - Set up systemd services and timers for daily and weekly runs (see "Automated Runs" section).
   - Configure the Telegram bot token and chat ID in the `.env` file.

## Usage

- To fetch reserves for all networks:
  ```
  make fetch-reserves
  ```

- To mint to treasury for a specific network:
  ```
  make mint NETWORK=MAINNET
  ```

- The automated script runs daily for L2 networks and weekly for MAINNET at 8:00 AM UTC.

## Automated Runs

To set up automated runs, you need to create systemd service and timer files.

1. Create and edit service files:
   ```
   sudo nano /etc/systemd/system/dolce-vita-daily.service
   sudo nano /etc/systemd/system/dolce-vita-weekly.service
   ```

2. Create and edit timer files:
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

Note: After cloning the repository, make sure to update the paths in the systemd service files to match the location where you've cloned the project. Replace `/home/yourusername/` with the path to your home directory or wherever you've placed the project.

## Monitoring

The script sends Telegram notifications for:
- Start of each run
- Successful completion of each run
- Any errors encountered during the run

To manually trigger a run:
```
./dolce_vita_collector_with_notifications.sh --l2s-only
```

For a MAINNET run:
```
./dolce_vita_collector_with_notifications.sh --mainnet-only
```

Note: Make sure you're in the project directory when running these commands, or use the full path to the script from your home directory:

```
~/dolce_vita_collector/dolce_vita_collector_with_notifications.sh --l2s-only
```

or

```
~/dolce_vita_collector/dolce_vita_collector_with_notifications.sh --mainnet-only
```

## Logs

Logs are stored in the `logs` directory within the project folder:
- `dolce_vita_collector_log.txt`: Contains logs for both daily and weekly runs

## Customization

When setting up this project, make sure to:
1. Update all paths in the scripts and service files to match your system's directory structure.
2. Configure your own Telegram bot token and chat ID in the `.env` file.
3. Adjust the systemd service files to use the correct user and group for your system.
4. If you've cloned this repository to a different location, update the paths in the systemd service files accordingly.

## Supported Networks

The script supports the following networks:
- MAINNET (weekly run)
- AVALANCHE
- OPTIMISM
- POLYGON
- ARBITRUM
- METIS
- BASE
- GNOSIS
- BNB
- SCROLL

L2 networks are processed in the daily run, while MAINNET is processed in the weekly run.

## Troubleshooting

If you encounter any issues:
1. Check the log file for error messages.
2. Ensure all environment variables in the `.env` file are correctly set.
3. Verify that the systemd services and timers are correctly configured and running.
4. Check your Telegram bot setup if you're not receiving notifications.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License.
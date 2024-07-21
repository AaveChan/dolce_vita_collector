# ACI's Dolce Vita Collector

This project automates the process of minting to treasury for various Aave Pools across multiple networks.

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

## Usage

- To fetch reserves for all networks:
  ```
  make fetch-reserves
  ```

- To mint to treasury for a specific network and pool:
  ```
  make mint-to-treasury NETWORK=MAINNET POOL=MAIN
  ```

- To run the entire process (fetch reserves and mint for all networks):
  ```
  make run-all
  ```

## License

This project is licensed under the MIT License.
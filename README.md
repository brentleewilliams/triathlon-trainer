# Triathlon Trainer

iOS app for Ironman 70.3 training tracking with HealthKit integration and Claude AI coaching.

## Quick Start

1. **Clone and Setup**
   ```bash
   git clone https://github.com/brentleewilliams/triathlon-trainer.git
   cd triathlon-trainer/IronmanTrainer
   ```

2. **Configure Secrets**
   ```bash
   cp IronmanTrainer/Config.example.plist IronmanTrainer/Config.plist
   ```

   Edit `IronmanTrainer/Config.plist` and add your API keys:
   ```xml
   <key>ANTHROPIC_API_KEY</key>
   <string>sk-ant-api03-YOUR_KEY_HERE</string>
   <key>LANGSMITH_API_KEY</key>
   <string>lsv2_YOUR_KEY_HERE</string>
   ```

3. **Build & Run**
   - Open `IronmanTrainer.xcodeproj` in Xcode
   - Select a simulator or device
   - Build and run (Cmd+R)

## Secrets File Location

**File:** `IronmanTrainer/IronmanTrainer/Config.plist`

This file contains your API keys and **is NOT committed to version control** (it's in `.gitignore`). Each developer must:
1. Copy `Config.example.plist` to `Config.plist`
2. Add their own API keys
3. Never commit `Config.plist`

## Getting API Keys

- **Anthropic Claude API:** [api.anthropic.com](https://api.anthropic.com)
- **LangSmith** (optional): [smith.langchain.com](https://smith.langchain.com)

## Features

- HealthKit integration for automatic workout sync
- 17-week training plan for Ironman 70.3 Oregon
- Claude AI coaching assistant with training context
- Analytics dashboard with volume and zone tracking
- Day-by-day workout planning and completion tracking

## Documentation

See [IronmanTrainer/README.md](./IronmanTrainer/README.md) for detailed architecture and feature documentation.

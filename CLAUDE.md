# triathlon-trainer

iOS race coaching app repo. The Xcode project lives at `IronmanTrainer/`.

**Full project spec:** `IronmanTrainer/CLAUDE.md`
**Product decisions and roadmap:** `IronmanTrainer/PRODUCT.md`
**Competitive analysis:** `IronmanTrainer/product-planning-and-differentiation.md`

## Repo structure

```
triathlon-trainer/
├── IronmanTrainer/          ← Xcode project (all Swift source, tests, CLAUDE.md)
│   ├── IronmanTrainer/      ← App source
│   ├── IronmanTrainerTests/ ← Unit tests
│   ├── functions/           ← Firebase Cloud Functions (Node.js)
│   └── docs/                ← Feature specs and plans
└── CLAUDE.md                ← this file
```

## Build

```bash
xcodebuild build -scheme IronmanTrainer -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test  -scheme IronmanTrainer -destination 'platform=iOS Simulator,name=iPhone 16'
```

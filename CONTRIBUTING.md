# Contributing

## Prerequisites

- Docker with buildx support
- Bash 4.0+
- Mikrotik RouterOS device for integration testing (optional)

## Development Workflow

### Building

The `build` script runs all stages: lint → build → test → scan → push.

```bash
./build              # Local build and test
./build --push       # Push to Docker Hub
./build --help       # See all options
```

### Testing

Run the test suite against a locally built image:

```bash
./build --no-scan --no-push
```

Or manually:

```bash
docker buildx build -t mokerlink-backup:test .
bash test/run-all TAG=test
```

### Code Style

All shell scripts must pass:

```bash
shellcheck src/**/*.sh test/*.sh
hadolint Dockerfile
```

The `./build` stage runs these automatically.

### Submitting Changes

1. Create a branch from `dev`
2. Make your changes
3. Run `./build` to lint, test, and scan
4. Submit a pull request to the `dev` branch

## Release Process

Releases are tagged with semantic versions:

```bash
./build --push --version 1.2.3
```

Tags trigger a multi-platform build and push to Docker Hub, plus SLSA provenance and SBOM generation.

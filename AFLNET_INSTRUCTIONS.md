# AFLNet LightFTP Fuzzing Tutorial

This guide walks you through running a **complete AFLNet fuzzing experiment** on the **LightFTP FTP server**, comparing fuzzing with and without state-aware mode (`-E` flag).

## Why LightFTP?

✅ **LightFTP is faster and more reliable than Live555**:
- Simpler FTP protocol (vs complex RTSP streaming)
- No timeout issues
- Quick test case execution
- Ready-to-use seed corpus included

---

## Prerequisites

1. **Docker** installed on your macOS machine
2. **AFLNet Docker image** built from `aflnet/aflnet/Dockerfile`

---

## Quick Start

### 1. Build the Docker Image (if not already built)

```bash
cd /Users/aprillexi/Desktop/cmu_programming/aflnet/aflnet
docker build -t aflnet-image .
```

### 2. Copy the Tutorial Script into the Container

First, start a container:

```bash
docker run -it --name aflnet-container aflnet-image bash
```

From another terminal, copy the script:

```bash
docker cp /Users/aprillexi/Desktop/cmu_programming/aflnet/aflnet/aflnet_lightftp_tutorial.sh aflnet-container:/opt/aflnet/
```

### 3. Run the Fuzzing Experiment

Inside the container:

```bash
cd /opt/aflnet
chmod +x aflnet_lightftp_tutorial.sh
./aflnet_lightftp_tutorial.sh 120  # Runs for 2 minutes per experiment
```

**Or use a custom duration** (in seconds):

```bash
./aflnet_lightftp_tutorial.sh 300  # 5 minutes per experiment
./aflnet_lightftp_tutorial.sh 60   # 1 minute per experiment (quick test)
```

---

## What the Script Does

The script automates the entire fuzzing workflow:

1. **Downloads and compiles LightFTP** with AFL instrumentation
2. **Experiment 1**: Fuzzes WITHOUT `-E` flag (baseline, queue-based)
3. **Experiment 2**: Fuzzes WITH `-E` flag (state-aware, protocol guided)
4. **Generates comparison report** showing paths, crashes, hangs, and states

---

## Understanding the Results

After running, you'll see:

```
========================================
         RESULTS COMPARISON
========================================

WITHOUT -E (Baseline Fuzzing):
-------------------------------
  Paths discovered: 45
  Crashes found: 0
  Hangs found: 0
  
WITH -E (State-Aware Fuzzing):
-------------------------------
  Paths discovered: 132
  Crashes found: 2
  Hangs found: 1
  States explored: 7

Key Findings:
-------------
- Path increase: 87 more paths with state-awareness
- State-aware mode explicitly models FTP protocol states
- Check ipsm.dot for the inferred state machine
```

### Key Metrics

| Metric | Description |
|--------|-------------|
| **Paths discovered** | Unique execution paths (code coverage proxy) |
| **Crashes** | Test cases that caused server crashes |
| **Hangs** | Test cases that caused timeouts |
| **States explored** | FTP protocol states discovered (WITH `-E` only) |

---

## Files Generated

Inside the container at `/home/LightFTP/Source/Release/`:

```
├── out-no-state/          # Baseline fuzzing output
│   ├── queue/             # Test cases found
│   ├── crashes/           # Raw crashes
│   ├── hangs/             # Raw hangs
│   └── replayable-*/      # Verified crashes/hangs
│
├── out-with-state/        # State-aware fuzzing output
│   ├── queue/             # Test cases (tagged with states)
│   ├── ipsm.dot           # Inferred protocol state machine
│   ├── crashes/
│   └── hangs/
│
├── state_machine.png      # Visual state machine graph
└── results_comparison.txt # Summary report
```

---

## Viewing the State Machine

To copy the state machine diagram to your Mac:

```bash
# Find your container name/ID
docker ps -a

# Copy the file
docker cp <container_name>:/home/LightFTP/Source/Release/state_machine.png ~/Desktop/
```

The state machine shows how AFLNet models the FTP protocol as states and transitions based on server responses.

---

## AFLNet Options Explained

### Experiment 1 (WITHOUT -E):

```bash
afl-fuzz \
  -i $AFLNET/tutorials/lightftp/in-ftp \  # Seed corpus
  -o out-no-state \                       # Output directory
  -N tcp://127.0.0.1/2200 \               # Network target
  -P FTP \                                # Protocol
  -D 10000 \                              # Response timeout (ms)
  -h 1 \                                  # Queue-based seed schedule
  -c ./ftpclean.sh \                      # Cleanup script
  ./fftp fftp.conf 2200                   # Server command
```

### Experiment 2 (WITH -E):

```bash
afl-fuzz -d \                             # Skip deterministic stage
  -i $AFLNET/tutorials/lightftp/in-ftp \
  -o out-with-state \
  -N tcp://127.0.0.1/2200 \
  -x $AFLNET/tutorials/lightftp/ftp.dict \ # Protocol dictionary
  -P FTP \
  -D 10000 \
  -q 3 \                                  # Region-level mutations
  -s 3 \                                  # IPSM seed selection
  -E \                                    # ⭐ Enable state-aware mode
  -R \                                    # Server is forking
  -c ./ftpclean.sh \
  ./fftp fftp.conf 2200
```

**Key difference**: The `-E` flag enables AFLNet to:
- Build a state machine from server responses
- Prioritize test cases that explore new states
- Guide mutations based on protocol structure

---

## Troubleshooting

### "Permission denied" when running script

```bash
chmod +x /opt/aflnet/aflnet_lightftp_tutorial.sh
```

### Container stops immediately

Check Docker logs:

```bash
docker logs aflnet-container
```

### Want to start fresh?

```bash
docker rm aflnet-container
docker run -it --name aflnet-container aflnet-image bash
```

### Test if LightFTP works manually

Inside container:

```bash
cd /home/LightFTP/Source/Release
./fftp fftp.conf 2200 &
telnet 127.0.0.1 2200
# Login with: USER ubuntu / PASS ubuntu
```

---

## Understanding FTP Protocol States

When you run WITH `-E`, AFLNet discovers states like:

1. **Initial** → Server waiting for connection
2. **Connected** → After TCP handshake
3. **Username provided** → After `USER ubuntu`
4. **Authenticated** → After `PASS ubuntu`
5. **Directory listed** → After `LIST`
6. **File transferred** → After `RETR filename`
7. **Disconnected** → After `QUIT`

The state machine (`ipsm.dot`) shows these transitions!

---

## Next Steps

- **Analyze crashes**: Check `out-with-state/replayable-crashes/` for interesting bugs
- **Replay test cases**: Use `aflnet-replay` tool to reproduce findings
- **Increase fuzzing time**: Run for hours/days for deeper coverage
- **Try other protocols**: Check `/opt/aflnet/tutorials/` for MQTT, DTLS, DNS examples

---

## References

- [AFLNet GitHub](https://github.com/aflnet/aflnet)
- [LightFTP Tutorial](https://github.com/aflnet/aflnet/tree/master/tutorials/lightftp)
- [Original AFL Documentation](https://github.com/google/AFL)

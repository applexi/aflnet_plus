# AFLNet+ : Content-Aware State Fuzzing

**AFLNet+** is an enhancement to [AFLNet](https://github.com/aflnet/aflnet) that introduces **content-aware state identification** for more precise stateful protocol fuzzing.

## The Problem with Original AFLNet

AFLNet identifies protocol states using only the **numeric response code**. For example, in FTP:
- `"220 LightFTP server ready\r\n"` → State **220**
- `"530 Invalid user name or password\r\n"` → State **530**
- `"530 This account is disabled\r\n"` → State **530** (same!)

This means AFLNet treats responses with the **same code but different meanings** as identical states, even though they represent different server behaviors and code paths.

### LightFTP Example

LightFTP has 13+ distinct response messages that map to only 8 unique response codes:

| Code | Variants | Server Behavior |
|------|----------|-----------------|
| **530** | 3 | "Please login", "Account disabled", "Invalid password" |
| **550** | 5 | "Permission denied", "File unavailable", "Resource busy", etc. |
| **200** | 3 | "Command okay", "Type set to A", "Type set to I" |

Original AFLNet collapses all 530 responses into one state, missing opportunities to explore the disabled account handling code and password validation code separately.

## AFLNet+ Solution

AFLNet+ creates unique states by hashing **both the response code AND the response content**:

```
Original AFLNet:
  "530 Invalid password"  → State 5
  "530 Account disabled"  → State 5  (same!)

AFLNet+:
  "530 Invalid password"  → hash("530 Invalid password") → State 5
  "530 Account disabled"  → hash("530 Account disabled") → State 6  (different!)
```

### Normalization

To prevent **state explosion** from variable data (like IP addresses in PASV responses), AFLNet+ normalizes responses before hashing:

```
"227 Entering Passive Mode (192,168,1,1,195,149)\r\n" → normalized → "227 Entering Passive Mode (X,X,X,X,X,X)"
"227 Entering Passive Mode (192,168,1,1,195,150)\r\n" → normalized → "227 Entering Passive Mode (X,X,X,X,X,X)"
                                                                       ↓
                                                                   Same state (good!)
```

## Building AFLNet+

```bash
cd aflnet
make clean
make

# For LLVM mode (recommended):
cd llvm_mode
make
```

## Usage

AFLNet+ is **enabled by default**. Use it exactly like regular AFLNet:

```bash
afl-fuzz -d -i in -o out -N tcp://127.0.0.1/2200 \
         -x ftp.dict -P FTP -D 10000 -q 3 -s 3 -E -K \
         ./fftp fftp.conf 2200
```

### Disabling Content Hashing

To revert to original AFLNet behavior, comment out this line in `config.h`:

```c
// #define AFLNET_PLUS_CONTENT_HASH 1
```

Then rebuild.

## Implementation Details

### Modified Files

| File | Changes |
|------|---------|
| `config.h` | Added `AFLNET_PLUS_CONTENT_HASH` flag and version bump |
| `aflnet.h` | Added content hash fields to `state_info_t`, new function declarations |
| `aflnet.c` | Added hash functions and content-aware state mapping |

### New Functions

```c
/* Compute 32-bit hash of response content using djb2 algorithm */
u32 hash_response_content(unsigned char* buf, unsigned int len);

/* Normalize response content before hashing (removes variable data) */
u32 normalize_and_hash_response(unsigned char* buf, unsigned int len, u32 response_code);

/* Enhanced state mapping using combined (code, content_hash) key */
u32 get_mapped_message_code_with_hash(u32 ori_message_code, u32 content_hash);
```

### State Info Structure Enhancement

```c
typedef struct {
  // ... existing fields ...
  
  /* AFLNet+ Enhancement */
  u32 content_hash;       /* hash of response content that created this state */
  u32 original_code;      /* original response code before mapping */
  u8 response_varies;     /* flag: different content seen for same code? */
  u32 unique_responses;   /* count of unique response contents for this code */
} state_info_t;
```

## Expected Results

| Metric | Expected Change |
|--------|-----------------|
| **States discovered** | ↑ 50-100% more for protocols with varied responses |
| **Code coverage** | ↑ 5-15% improvement |
| **Unique paths** | ↑ More paths from previously collapsed states |
| **Fuzzing speed** | ↓ ~10% slower (more states to track) |

## Supported Protocols

Currently, content-aware hashing is implemented for:
- **FTP** (LightFTP, ProFTPD, etc.)

Other protocols (SMTP, RTSP, SSH, etc.) can be enhanced by modifying their respective `extract_response_codes_*` functions.

## Citation

If you use AFLNet+ in your research, please cite both the original AFLNet paper and this enhancement:

```bibtex
@inproceedings{aflnet,
  title={AFLNet: A Greybox Fuzzer for Network Protocols},
  author={Pham, Van-Thuan and B{\"o}hme, Marcel and Roychoudhury, Abhik},
  booktitle={IEEE International Conference on Software Testing, Verification and Validation (ICST)},
  year={2020}
}
```

## License

AFLNet+ is released under the same Apache License 2.0 as the original AFLNet.

## Authors

- **AFLNet**: Van-Thuan Pham, Marcel Böhme, Abhik Roychoudhury
- **AFLNet+ Content Hashing Enhancement**: [Your Name]

## References

- [Original AFLNet](https://github.com/aflnet/aflnet)
- [AFLNet Paper (ICST 2020)](https://thuanpv.github.io/publications/AFLNet_ICST20.pdf)
- [ProFuzzBench](https://github.com/profuzzbench/profuzzbench)


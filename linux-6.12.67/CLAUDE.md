# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Current Build Configuration

Linux 6.12.67 "Baby Opossum Posse" — x86_64, compiled with GCC 13.3.0.

Key config choices: modular kernel (`CONFIG_MODULES=y`), SLUB allocator, voluntary preemption with dynamic preempt, NUMA/SMP enabled, SELinux, KVM guest support, ftrace/tracing enabled, cgroups and namespaces.

## Build Commands

```bash
# Configure
make defconfig              # Default config for current architecture
make menuconfig             # Interactive configuration (requires ncurses)
make oldconfig              # Update existing .config, prompt for new options
make olddefconfig           # Update .config using defaults for new options

# Build
make -j$(nproc)             # Build kernel and modules
make vmlinux                # Build kernel image only
make modules                # Build modules only
make path/to/file.o         # Compile single object file (quick syntax check)
make path/to/file.i         # Preprocess only
make path/to/file.s         # Generate assembly

# Module-only build
make M=path/to/module       # Build single module directory
make M=path/to/module clean # Clean single module

# Clean
make clean                  # Remove build artifacts, keep .config
make mrproper               # Remove all generated files including .config

# Code quality
scripts/checkpatch.pl -f <file>   # Check coding style of a file
scripts/checkpatch.pl -g HEAD     # Check last commit
make C=1                          # Run sparse on changed files
make C=2                          # Run sparse on all files
make coccicheck                   # Semantic checking with Coccinelle

# Testing
make kselftest                    # Build and run kernel self-tests
make TARGETS=mm kselftest         # Run tests for specific subsystem
./tools/testing/kunit/kunit.py run                          # Run all KUnit tests
./tools/testing/kunit/kunit.py run "suite_name"             # Run specific test suite
./tools/testing/kunit/kunit.py run "suite.test_case"        # Run specific test case
./tools/testing/kunit/kunit.py run --kunitconfig=path       # Use subsystem kunitconfig
```

**Build variables:** `ARCH=<arch>`, `CROSS_COMPILE=<prefix>`, `LLVM=1` (use Clang), `O=<dir>` (out-of-tree build), `V=1` (verbose), `W=1` (extra warnings).

## Architecture Overview

### Build System (Kbuild)

- `.config` at root contains all configuration options
- `Kconfig` files define config options hierarchically; each directory has a `Makefile`
- `obj-y` = built-in, `obj-m` = module, controlled by `CONFIG_*` variables
- Docs: `Documentation/kbuild/`

### Boot Flow

`init/main.c:start_kernel()` is the architecture-independent entry point after arch-specific early boot. It initializes subsystems in a specific order: memory (`mm_core_init()`), scheduler, RCU, VFS, workqueues, then launches `kernel_init()` which becomes PID 1 (init process).

### Syscall Entry Path (x86_64)

- `arch/x86/entry/entry_64.S` — assembly entry for syscalls, interrupts, exceptions
- `arch/x86/entry/common.c` — `do_syscall_64()` dispatches to syscall handlers
- `arch/x86/entry/syscalls/syscall_64.tbl` — syscall number-to-function mapping
- Doc: `Documentation/arch/x86/entry_64.rst`

### Device/Driver Model

Unified device model lives in `drivers/base/`. Core abstractions defined in `include/linux/device.h`: `struct device`, `device_driver`, `bus_type`. All devices attach to buses using probe/remove callbacks. Uses kobjects for reference counting and sysfs integration. Device resource management (devres) provides automatic cleanup. Docs: `Documentation/driver-api/driver-model/`.

### Key Header Files

These define the kernel's fundamental abstractions:

- **Tasks/scheduling**: `include/linux/sched.h` — `struct task_struct` and scheduler APIs
- **VFS**: `include/linux/fs.h` — `struct inode`, `file`, `super_block`, `file_operations`
- **Memory**: `include/linux/mm.h`, `include/linux/gfp.h` — page allocation, virtual memory
- **Devices**: `include/linux/device.h` — unified device model
- **Synchronization**: `include/linux/mutex.h`, `spinlock.h`, `rwsem.h`, `atomic.h`
- **Data structures**: `include/linux/list.h` (intrusive linked lists), `rbtree.h`, `xarray.h`
- **Work deferral**: `include/linux/workqueue.h`, `timer.h`, `interrupt.h` (tasklets, softirqs)
- **RCU**: `include/linux/rcupdate.h` — read-copy-update for lockless reads

### Concurrency Model

This kernel uses voluntary preemption with `CONFIG_PREEMPT_DYNAMIC` (runtime-switchable). SMP and NUMA are enabled. Key primitives: spinlocks (non-sleeping, IRQ contexts), mutexes (sleeping), RCU (lockless read-side), per-CPU variables, atomic operations. Always consider: can this code sleep? Is it in interrupt context? Use `might_sleep()` to assert sleepable context.

### Directory Structure

- **arch/** — Architecture-specific code; each has Makefile and `arch/*/configs/`
- **kernel/** — Core: scheduler (`kernel/sched/`), signals, BPF, kprobes, futex, tracing
- **mm/** — Memory management: page allocator, SLUB, vmalloc, mmap, page reclaim
- **fs/** — Filesystems (ext4, btrfs, nfs, proc, sysfs) and VFS layer
- **drivers/** — Device drivers by subsystem (gpu, net, usb, acpi, nvme, etc.)
- **net/** — Networking stack (IPv4/6, sockets, netfilter, TCP, UDP)
- **block/** — Block device layer and I/O schedulers
- **security/** — LSM framework, SELinux, AppArmor
- **init/** — Boot and initialization (`start_kernel()`)
- **lib/** — Shared library routines (string, sort, compression, data structures)
- **include/** — Public headers; arch-specific in `arch/*/include/`
- **tools/** — User-space tools (perf, bpf, testing)
- **scripts/** — Build system and development tools

## Coding Style

See `Documentation/process/coding-style.rst`:

- 8-character tabs for indentation (not spaces)
- If code needs >3 indentation levels, refactor
- Functions: opening brace on **next line**. Control structures: opening brace on **same line**
- Pointer declarations: `char *p` not `char* p`
- Space after keywords (`if`, `for`, `while`) but NOT after `sizeof`, `typeof`, `__attribute__`
- Use `fallthrough;` keyword for intentional switch case fallthrough
- Use kernel types: `u32`, `s64`, `__be16`, etc.
- Prefer `allowlist`/`denylist` over `whitelist`/`blacklist`; `primary`/`secondary` over `master`/`slave`

## Debugging and Development Tools

```bash
# IDE integration
scripts/clang-tools/gen_compile_commands.py    # Generate compile_commands.json

# Config manipulation
scripts/config --enable CONFIG_OPTION
scripts/config --disable CONFIG_OPTION
scripts/config --module CONFIG_OPTION
scripts/config --file .config -s CONFIG_OPTION  # Query a config value

# Crash/oops analysis
scripts/decode_stacktrace.sh vmlinux < oops.txt
scripts/faddr2line vmlinux function_name+0xoffset  # Translate func+offset to source:line

# Size analysis
scripts/bloat-o-meter old_vmlinux new_vmlinux   # Compare kernel sizes between builds

# Kconfig validation
scripts/checkkconfigsymbols.py                  # Find undefined/redundant Kconfig symbols

# GDB debugging
scripts/gdb/vmlinux-gdb.py                      # Kernel GDB helpers (load in GDB)

# Symbol database
make cscope                                     # Build cscope database
make tags                                       # Build ctags database
```

## Key Files

- **MAINTAINERS** — Subsystem owners; use `scripts/get_maintainer.pl <file>` to query
- **Documentation/process/changes.rst** — Required tool versions
- **Documentation/process/submitting-patches.rst** — Patch submission guide
- **Documentation/core-api/** — Kernel API docs (kobjects, workqueues, data structures)
- **Documentation/driver-api/** — Driver development docs

## Common Patterns

### Adding a New Source File

1. Create the `.c` file in the appropriate directory
2. Add to the directory's `Makefile`: `obj-$(CONFIG_FEATURE) += file.o` (or `obj-y` for always built-in)
3. If adding a new config option, add entry to the relevant `Kconfig` file

### Adding a KUnit Test

1. Create `lib/foo_kunit.c` (or co-locate with tested code)
2. Add `obj-$(CONFIG_FOO_KUNIT_TEST) += foo_kunit.o` to the directory Makefile
3. Add a `config FOO_KUNIT_TEST` entry in Kconfig depending on `KUNIT`
4. Run: `./tools/testing/kunit/kunit.py run "foo_test_suite"`

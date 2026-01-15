# Docker Containers Under The Hood - Deep Dive

> A comprehensive guide to understanding how Docker containers really work at the Linux kernel level. Perfect for YouTube demos on Rocky Linux or any RHEL-based distribution.

## 🎯 What You'll Learn

This demo explores the core Linux technologies that power Docker containers:

- **Linux Namespaces** - How containers achieve process isolation
- **Control Groups (cgroups)** - How resources are limited and controlled
- **OverlayFS** - How layered filesystems work
- **Network Isolation** - How virtual networks are created
- **Process Management** - Why containers are just isolated processes

## 📋 Prerequisites

**System Requirements:**
- Rocky Linux (or any RHEL-based distro)
- Docker installed and running
- Root/sudo access
- Basic Linux command line knowledge

**Install Docker on Rocky Linux:**
```bash
# Add Docker repository
sudo dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo

# Install Docker
sudo dnf install -y docker-ce docker-ce-cli containerd.io

# Start and enable Docker
sudo systemctl start docker
sudo systemctl enable docker

# Verify installation
docker --version
sudo docker run hello-world
```

**Install Required Tools:**
```bash
# Network and process tools
sudo dnf install -y bridge-utils iproute-tc net-tools psmisc procps-ng util-linux

# JSON parsing tool (optional but helpful)
sudo dnf install -y jq

# Add your user to docker group (optional - to run without sudo)
sudo usermod -aG docker $USER
newgrp docker
```

---

## 🔍 Part 1: Linux Namespaces

Namespaces provide isolation - making each container think it's alone on the system.

### 🎯 What You'll Achieve

By the end of this section, you will:
- ✅ Understand how containers use namespaces for isolation
- ✅ See that containers are just processes with different namespace IDs
- ✅ Discover how PID namespaces make containers think they're PID 1
- ✅ Explore network isolation using network namespaces
- ✅ Learn to use `nsenter` to enter container namespaces
- ✅ Manually create your own namespace using `unshare`
- ✅ Prove that namespace isolation is what makes containers "feel" isolated

### Understanding Namespaces

Docker uses 6 types of namespaces:
- **PID** - Process isolation
- **NET** - Network stack isolation
- **MNT** - Mount points isolation
- **UTS** - Hostname isolation
- **IPC** - Inter-process communication isolation
- **USER** - User ID isolation

### Demo: Exploring Namespaces

> 📖 **Reference**: [Linux Namespaces Man Page](https://man7.org/linux/man-pages/man7/namespaces.7.html)

**Step 1: Start a container**
```bash
# Start a nginx container in detached mode (-d)
# This creates a new set of namespaces for isolation
docker run -d --name namespace-demo nginx:alpine

# Get the container ID for reference
CONTAINER_ID=$(docker ps -q -f name=namespace-demo)
echo "Container ID: $CONTAINER_ID"
```
**What's happening?** 
- Docker creates 6 new namespaces (PID, NET, MNT, UTS, IPC, USER)
- The nginx process is launched inside these isolated namespaces
- From the container's perspective, it's the only thing running

---

**Step 2: Find the container process on host**
```bash
# Every container is just a process on the host!
# Docker stores the main process ID in the container metadata
CONTAINER_PID=$(docker inspect -f '{{.State.Pid}}' namespace-demo)
echo "Container's main process PID: $CONTAINER_PID"

# View the process in the host's process table
ps aux | grep $CONTAINER_PID | grep -v grep
```
**What you'll see:**
- The PID will be a regular number like 12345
- You'll see the nginx process running as a normal host process
- This proves containers are NOT virtual machines - they're just processes!

**Why this matters:** The container thinks it's PID 1, but the host sees it as a different PID. This is PID namespace isolation in action.

---

**Step 3: Examine process namespaces**
```bash
# Each process in Linux has namespace information stored in /proc/<PID>/ns/
# Let's look at the container's namespaces
ls -la /proc/$CONTAINER_PID/ns/

# Now compare with the host's init process (PID 1) namespaces
echo "Host namespaces:"
ls -la /proc/1/ns/ | tail -n +4

echo "Container namespaces:"
ls -la /proc/$CONTAINER_PID/ns/ | tail -n +4

# Notice different inode numbers = different namespaces!
```
**Expected Output:**
```
Host namespaces:
lrwxrwxrwx. 1 root root 0 Jan  3 10:00 mnt -> 'mnt:[4026531840]'
lrwxrwxrwx. 1 root root 0 Jan  3 10:00 net -> 'net:[4026531992]'
...

Container namespaces:
lrwxrwxrwx. 1 root root 0 Jan  3 10:00 mnt -> 'mnt:[4026532574]'
lrwxrwxrwx. 1 root root 0 Jan  3 10:00 net -> 'net:[4026532676]'
...
```
**Key Point:** The numbers in brackets `[4026531840]` are inode numbers that uniquely identify namespaces. Different numbers = different namespaces = isolation!

**Step 4: PID namespace isolation**
```bash
# View processes from INSIDE the container
# The container is in its own PID namespace
docker exec namespace-demo ps aux

# Now view the same process from the HOST
echo "On host:"
ps aux | grep $CONTAINER_PID | grep -v grep | head -1
```
**What you'll see:**
- **Inside container:** nginx appears as PID 1 (the init process)
- **On host:** The same nginx appears as PID 12345 (or whatever $CONTAINER_PID is)

**Why this works:** PID namespaces create a separate PID number space. The kernel maintains two PID mappings:
- Inside the namespace: PIDs start from 1
- Outside the namespace: PIDs are from the global PID space

> 📖 **Deep Dive**: [PID Namespaces Documentation](https://man7.org/linux/man-pages/man7/pid_namespaces.7.html)

---

**Step 5: Network namespace isolation**
```bash
# View network interfaces from INSIDE the container
# Each container gets its own network stack
docker exec namespace-demo ip addr show

# Now view the HOST network interfaces
ip addr show
```
**What you'll see:**

*Inside container:*
```
1: lo: <LOOPBACK,UP,LOWER_UP> ...
    inet 127.0.0.1/8 scope host lo
4: eth0@if5: <BROADCAST,MULTICAST,UP,LOWER_UP> ...
    inet 172.17.0.2/16 brd 172.17.255.255 scope global eth0
```

*On host:*
```
1: lo: <LOOPBACK,UP> ...
2: eth0: <BROADCAST,MULTICAST,UP> ...
3: docker0: <BROADCAST,MULTICAST,UP> ...
5: veth1234@if4: <BROADCAST,MULTICAST,UP> ...
```

**Key Observations:**
- Container sees only `lo` and `eth0`
- Host sees many more interfaces including `docker0` bridge and `veth` pairs
- They have completely separate network stacks!

> 📖 **Deep Dive**: [Network Namespaces](https://man7.org/linux/man-pages/man7/network_namespaces.7.html)

**Step 6: Hostname isolation (UTS namespace)**
```bash
# Get hostname from INSIDE the container
docker exec namespace-demo hostname

# Get hostname from the HOST
hostname
```
**What you'll see:**
- Container hostname: Usually the first 12 chars of container ID (e.g., `a1b2c3d4e5f6`)
- Host hostname: Your actual server name (e.g., `rocky-linux-server`)

**What's a UTS namespace?** UTS stands for "UNIX Time Sharing" - it isolates:
- Hostname (`hostname` command)
- Domain name (`domainname` command)

This allows each container to have its own hostname without affecting the host or other containers.

> 📖 **Deep Dive**: [UTS Namespaces](https://man7.org/linux/man-pages/man7/uts_namespaces.7.html)

---

**Step 7: Enter container namespaces with nsenter**
```bash
# nsenter (namespace enter) lets you enter another process's namespaces
# Here we enter the container's network namespace (-n flag)
nsenter -t $CONTAINER_PID -n ip addr

# This shows network interfaces from container's perspective
```
**What's happening:** 
- `nsenter -t <PID>` targets a specific process
- `-n` means enter the network namespace
- Any command after that runs inside the container's network namespace

**Other nsenter flags:**
- `-p` : PID namespace
- `-m` : Mount namespace
- `-u` : UTS namespace
- `-i` : IPC namespace
- `-U` : User namespace

**Pro tip:** This is how `docker exec` works behind the scenes!

> 📖 **Reference**: [nsenter Man Page](https://man7.org/linux/man-pages/man1/nsenter.1.html)

---

**Step 8: Create your own namespace**
```bash
# unshare creates new namespaces (opposite of nsenter)
# Let's manually create a PID namespace like Docker does
unshare --pid --fork --mount-proc bash -c 'ps aux'

# Notice only 2 processes visible - just like a container!
```
**Expected Output:**
```
USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root         1  0.0  0.0  12345  1234 ?        S    10:30   0:00 bash -c ps aux
root         2  0.0  0.0  12345  1234 ?        R    10:30   0:00 ps aux
```

**What's happening:**
- `--pid` creates a new PID namespace
- `--fork` forks a child process in the new namespace
- `--mount-proc` mounts a new /proc filesystem
- You only see processes in your new namespace!

**This is the magic of containers!** Docker uses `unshare` (or rather, the `clone()` system call with namespace flags) to create isolated environments.

> 📖 **Deep Dive**: [unshare Man Page](https://man7.org/linux/man-pages/man1/unshare.1.html) | [clone() System Call](https://man7.org/linux/man-pages/man2/clone.2.html)

**Cleanup:**
```bash
docker stop namespace-demo
docker rm namespace-demo
```

---

## 🎛️ Part 2: Control Groups (cgroups)

Cgroups control and limit resource usage for containers.

### 🎯 What You'll Achieve

By the end of this section, you will:
- ✅ Understand how cgroups enforce resource limits on containers
- ✅ Identify whether your system uses cgroup v1 or v2
- ✅ Find and inspect a container's cgroup settings on the host
- ✅ Compare unlimited vs limited containers
- ✅ Set memory limits and watch the OOM killer enforce them
- ✅ Set CPU limits and see how they're enforced
- ✅ Navigate the cgroup filesystem hierarchy
- ✅ Monitor real-time resource usage with Docker stats

### Understanding Cgroups

Cgroups enable Docker to:
- Limit CPU usage
- Limit memory usage
- Limit disk I/O
- Track resource consumption
- Enforce resource guarantees

### Demo: Exploring Cgroups

> 📖 **Reference**: [Control Groups v2 Documentation](https://www.kernel.org/doc/html/latest/admin-guide/cgroup-v2.html) | [Red Hat Cgroups Guide](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/managing_monitoring_and_updating_the_kernel/assembly_using-cgroups-v2-to-control-distribution-of-cpu-time-for-applications_managing-monitoring-and-updating-the-kernel)

**Step 1: Check cgroup version**
```bash
# Linux has two cgroup versions: v1 (legacy) and v2 (modern unified hierarchy)
# Let's check which version your system uses
if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
    echo "System uses: cgroup v2 (unified hierarchy)"
else
    echo "System uses: cgroup v1 (legacy)"
fi
```
**What's the difference?**
- **cgroup v1**: Separate hierarchies for each resource (cpu, memory, io, etc.)
  - Located at: `/sys/fs/cgroup/cpu/`, `/sys/fs/cgroup/memory/`, etc.
- **cgroup v2**: Single unified hierarchy for all resources
  - Located at: `/sys/fs/cgroup/`
  - More flexible and easier to manage

**Rocky Linux:** Typically uses cgroup v2 by default (if kernel 4.5+)

> 📝 **Note:** The commands in this guide work for both versions, with notes where they differ.

---

**Step 2: Start container without limits**
```bash
# Start nginx without any resource restrictions
# Docker will create a cgroup but won't set limits
docker run -d --name cgroup-demo-unlimited nginx:alpine

# Find where the container's cgroup is located
CONTAINER_PID=$(docker inspect -f '{{.State.Pid}}' cgroup-demo-unlimited)
cat /proc/$CONTAINER_PID/cgroup
```
**Expected Output (cgroup v2):**
```
0::/system.slice/docker-a1b2c3d4e5f6.scope
```

**What this means:**
- `0::` indicates cgroup v2
- `/system.slice/` is the systemd slice
- `docker-a1b2c3d4e5f6.scope` is the container's cgroup

**For cgroup v1, you'll see:**
```
12:memory:/docker/a1b2c3d4e5f6...
11:cpu,cpuacct:/docker/a1b2c3d4e5f6...
...
```

---

**Step 3: Examine cgroup settings**
```bash
# Navigate to the container's cgroup directory
CGROUP_PATH=$(cat /proc/$CONTAINER_PID/cgroup | cut -d: -f3)
echo "Cgroup path: $CGROUP_PATH"

# For cgroup v2: Check memory limit
cat /sys/fs/cgroup$CGROUP_PATH/memory.max 2>/dev/null || echo "max (unlimited)"

# Check CPU settings
cat /sys/fs/cgroup$CGROUP_PATH/cpu.weight 2>/dev/null || echo "default weight (100)"
```
**What you'll see:**
- `memory.max` shows `max` - meaning unlimited memory
- `cpu.weight` shows `100` - default CPU priority (range: 1-10000)

**Key Cgroup Files (v2):**
- `memory.max` - Hard memory limit
- `memory.current` - Current memory usage
- `cpu.max` - CPU quota (e.g., "50000 100000" = 0.5 cores)
- `cpu.weight` - CPU priority/share
- `io.max` - I/O throttling
- `pids.max` - Maximum number of processes

> 📖 **Deep Dive**: [Cgroup v2 Interface Files](https://www.kernel.org/doc/html/latest/admin-guide/cgroup-v2.html#core-interface-files)

**Step 4: Start container WITH memory limit**
```bash
# Start container with 50MB memory limit
# Docker will configure the cgroup to enforce this limit
docker run -d --name cgroup-demo-limited --memory="50m" nginx:alpine

# Get PID and cgroup path
LIMITED_PID=$(docker inspect -f '{{.State.Pid}}' cgroup-demo-limited)
LIMITED_CGROUP=$(cat /proc/$LIMITED_PID/cgroup | cut -d: -f3)

# Check the enforced memory limit
cat /sys/fs/cgroup$LIMITED_CGROUP/memory.max
# Should show: 52428800 (50MB in bytes)
```
**What's happening:**
- Docker writes `52428800` to the cgroup's `memory.max` file
- The kernel enforces this limit automatically
- If the container tries to use more than 50MB, the **OOM (Out-Of-Memory) killer** terminates it

**Memory Limit Calculation:**
```
50 MB = 50 × 1024 × 1024 = 52,428,800 bytes
```

**Check current memory usage:**
```bash
cat /sys/fs/cgroup$LIMITED_CGROUP/memory.current
```

> 📖 **Deep Dive**: [Memory Cgroup Documentation](https://www.kernel.org/doc/html/latest/admin-guide/cgroup-v2.html#memory)

---

**Step 5: Start container WITH CPU limit**
```bash
# Start container limited to 0.5 CPU cores (50% of one core)
docker run -d --name cgroup-demo-cpu --cpus="0.5" nginx:alpine

# Check CPU quota
CPU_PID=$(docker inspect -f '{{.State.Pid}}' cgroup-demo-cpu)
CPU_CGROUP=$(cat /proc/$CPU_PID/cgroup | cut -d: -f3)

# View CPU limit (format: quota period)
cat /sys/fs/cgroup$CPU_CGROUP/cpu.max
# Shows: 50000 100000 = 0.5 cores (50000/100000)
```
**Understanding CPU limits:**
- Format: `$QUOTA $PERIOD` (both in microseconds)
- `50000 100000` means:
  - In every 100ms period (100000µs)
  - The container can use max 50ms of CPU time (50000µs)
  - 50ms / 100ms = 0.5 cores

**Examples:**
- 1 full core: `100000 100000`
- 2 cores: `200000 100000`
- 0.25 cores: `25000 100000`

**What happens if exceeded?** The container is throttled - its processes are paused until the next period.

> 📖 **Deep Dive**: [CPU Cgroup Documentation](https://www.kernel.org/doc/html/latest/admin-guide/cgroup-v2.html#cpu)

---

**Step 6: Monitor resource usage**
```bash
# View real-time resource usage for all containers
docker stats --no-stream cgroup-demo-unlimited cgroup-demo-limited cgroup-demo-cpu
```
**Expected Output:**
```
CONTAINER           CPU %     MEM USAGE / LIMIT   MEM %     NET I/O     BLOCK I/O
cgroup-demo-unlimited   0.01%     2.5MiB / 15.5GiB    0.02%     796B / 0B   0B / 0B
cgroup-demo-limited     0.01%     2.5MiB / 50MiB      5.00%     796B / 0B   0B / 0B
cgroup-demo-cpu         0.01%     2.5MiB / 15.5GiB    0.02%     796B / 0B   0B / 0B
```

**What each column means:**
- **CPU %**: Current CPU usage percentage
- **MEM USAGE / LIMIT**: Current memory vs limit
- **MEM %**: Percentage of available memory used
- **NET I/O**: Network bytes in/out
- **BLOCK I/O**: Disk bytes read/written

**Behind the scenes:** `docker stats` reads from:
- `cpu.stat` - CPU usage statistics
- `memory.current` - Current memory usage
- `io.stat` - I/O statistics

---

**Step 7: Test memory limit enforcement**
```bash
# Try to allocate 100MB in a container limited to 50MB
# This should trigger the OOM killer
docker exec cgroup-demo-limited sh -c 'dd if=/dev/zero of=/tmp/test bs=1M count=100' || echo "Killed by OOM!"

# Check if container was killed
docker ps -a | grep cgroup-demo-limited
```
**What happens:**
1. `dd` command tries to write 100MB to memory
2. Memory usage exceeds the 50MB limit
3. Kernel's **OOM killer** intervenes
4. OOM killer selects and kills a process (usually the `dd` command)
5. If the main container process is killed, Docker marks it as exited

**Check OOM events:**
```bash
# View OOM kill count
cat /sys/fs/cgroup$LIMITED_CGROUP/memory.events | grep oom_kill
```

**This proves:** Cgroups are enforced by the kernel, not by Docker!

> 📖 **Deep Dive**: [Linux OOM Killer](https://www.kernel.org/doc/gorman/html/understand/understand016.html)

**Step 8: View cgroup hierarchy**
```bash
# Docker creates cgroups in a hierarchy
find /sys/fs/cgroup -name "*docker*" 2>/dev/null | head -10
```

**Cleanup:**
```bash
docker stop cgroup-demo-unlimited cgroup-demo-limited cgroup-demo-cpu
docker rm cgroup-demo-unlimited cgroup-demo-limited cgroup-demo-cpu
```

---

## 📦 Part 3: Layered Filesystems (OverlayFS)

Docker uses a union filesystem to efficiently manage container storage.

### 🎯 What You'll Achieve

By the end of this section, you will:
- ✅ Understand how Docker images are built from layers
- ✅ Identify the storage driver Docker is using (overlay2)
- ✅ Examine individual image layers and their sizes
- ✅ Find where layers are stored on disk (`/var/lib/docker/overlay2/`)
- ✅ See the difference between UpperDir (writable) and LowerDir (read-only)
- ✅ Demonstrate Copy-on-Write by modifying files
- ✅ Prove that multiple containers share the same image layers
- ✅ Track disk usage and understand layer reuse benefits
- ✅ Create custom images by committing container changes

### Understanding Layered Filesystems

> 📖 **Reference**: [OverlayFS Documentation](https://www.kernel.org/doc/html/latest/filesystems/overlayfs.html) | [Docker Storage Drivers](https://docs.docker.com/storage/storagedriver/) | [Understanding Image Layers](https://docs.docker.com/build/guide/layers/)

- Images are made of **read-only layers** (stacked like a cake)
- Containers add a **thin writable layer** on top
- **Copy-on-Write (CoW)** optimizes storage
- Multiple containers can **share image layers**
- Common storage driver: **overlay2** (uses OverlayFS)

**How OverlayFS Works:**
```
┌─────────────────────────────┐
│  Container Writable Layer   │  ← New files & modifications
├─────────────────────────────┤
│   Image Layer 3 (nginx)     │  ← Read-only
├─────────────────────────────┤
│   Image Layer 2 (alpine)    │  ← Read-only
├─────────────────────────────┤
│   Image Layer 1 (base)      │  ← Read-only
└─────────────────────────────┘
```

**Key Directories:**
- **LowerDir**: Stack of read-only image layers
- **UpperDir**: Container's writable layer (stores changes)
- **MergedDir**: Union view of all layers (what container sees)
- **WorkDir**: OverlayFS working directory

### Demo: Exploring Filesystem Layers

**Step 1: Check storage driver**
```bash
# View Docker's storage driver (how it manages container filesystems)
docker info | grep "Storage Driver"

# View Docker root directory (where all data is stored)
docker info | grep "Docker Root Dir"
```
**Expected Output:**
```
Storage Driver: overlay2
Docker Root Dir: /var/lib/docker
```

**Storage Driver Options:**
- **overlay2** (recommended): Uses OverlayFS kernel driver - fast and efficient
- **devicemapper**: Block-level storage (legacy)
- **btrfs/zfs**: Advanced filesystems with snapshots
- **vfs**: No CoW - uses deep copy (slow, testing only)

**Why overlay2?** It's the default on modern Linux - fast, efficient, and well-tested.

---

**Step 2: Examine Docker data directory**
```bash
# List Docker's data directory structure
sudo ls -lh /var/lib/docker/
```
**Expected Output:**
```
drwx--x--x. 4 root root   43 Jan  3 10:00 buildkit
drwx--x---. 4 root root   92 Jan  3 10:00 containers
drwx------. 3 root root   22 Jan  3 10:00 image
drwxr-x---. 3 root root   19 Jan  3 10:00 network
drwx--x---. 5 root root 4.0K Jan  3 10:00 overlay2
drwx------. 4 root root   32 Jan  3 10:00 plugins
drwx------. 2 root root    6 Jan  3 10:00 runtimes
drwx------. 2 root root    6 Jan  3 10:00 swarm
drwx------. 2 root root    6 Jan  3 10:00 tmp
drwx------. 2 root root    6 Jan  3 10:00 volumes
```

**Key Directories:**
- **overlay2/**: Actual filesystem layers stored here (most important!)
- **containers/**: Container metadata, logs, config files
- **image/**: Image metadata and layer relationships
- **volumes/**: Named volumes (persistent data)
- **network/**: Network configuration

📝 **Note**: Never manually modify files in `/var/lib/docker/` - use Docker commands instead!

**Step 3: Pull and examine image layers**
```bash
# Pull nginx image (watch the layers download)
docker pull nginx:alpine

# View image history (each layer)
docker history nginx:alpine

# Get detailed layer information
docker inspect nginx:alpine | jq '.[0].RootFS.Layers'
```

**Step 4: Explore layer storage**
```bash
# View overlay2 directory structure
sudo ls /var/lib/docker/overlay2/ | head -5

# Examine a sample layer
SAMPLE_LAYER=$(sudo ls /var/lib/docker/overlay2/ | head -1)
sudo ls -la /var/lib/docker/overlay2/$SAMPLE_LAYER/
```

**Step 5: Start container and examine filesystem**
```bash
# Start nginx container
docker run -d --name fs-demo nginx:alpine

# Get container's filesystem details
docker inspect fs-demo | jq '.[0].GraphDriver'

# Key directories:
# - UpperDir: Container's writable layer
# - LowerDir: Read-only image layers
# - MergedDir: Union view of all layers
```

**Step 6: View mount information**
```bash
# Get container PID
CONTAINER_PID=$(docker inspect -f '{{.State.Pid}}' fs-demo)

# View how overlay is mounted
cat /proc/$CONTAINER_PID/mountinfo | grep overlay
```

**Step 7: Demonstrate Copy-on-Write**
```bash
# Create a new file in container (goes to writable layer)
docker exec fs-demo sh -c 'echo "Hello World" > /usr/share/nginx/html/test.txt'

# Verify file exists
docker exec fs-demo cat /usr/share/nginx/html/test.txt

# Modify an existing file from image layer
docker exec fs-demo sh -c 'echo "Modified!" >> /etc/nginx/nginx.conf'
# Docker copied the file to writable layer before modifying it
```

**Step 8: Find files in writable layer**
```bash
# Get the writable layer directory
UPPER_DIR=$(docker inspect fs-demo | jq -r '.[0].GraphDriver.Data.UpperDir')
echo "Writable layer: $UPPER_DIR"

# List files in writable layer
sudo find $UPPER_DIR -type f 2>/dev/null | head -10

# View our test file
sudo cat "$UPPER_DIR/usr/share/nginx/html/test.txt"
```

**Step 9: Demonstrate layer reuse**
```bash
# Start second container from same image
docker run -d --name fs-demo-2 nginx:alpine

# Both containers share image layers, only writable layer differs
docker ps -s --filter name=fs-demo

# SIZE = writable layer size
# VIRTUAL SIZE = writable layer + all shared image layers
```

**Step 10: Check disk usage**
```bash
# Docker disk usage breakdown
docker system df

# Detailed view
docker system df -v
```

**Step 11: Commit container to image**
```bash
# Create image from modified container
docker commit fs-demo nginx-custom:v1

# View the new image's layers
docker history nginx-custom:v1

# Top layer contains our changes
```

**Cleanup:**
```bash
docker stop fs-demo fs-demo-2
docker rm fs-demo fs-demo-2
docker rmi nginx-custom:v1
```

---

## 🌐 Part 4: Network Isolation

Docker creates virtual networks using Linux networking technologies.

### 🎯 What You'll Achieve

By the end of this section, you will:
- ✅ Understand how Docker uses veth pairs to connect containers
- ✅ See the docker0 bridge and how it forwards traffic
- ✅ Watch new network interfaces appear when containers start
- ✅ Find a container's virtual ethernet pair on the host
- ✅ Examine iptables rules for NAT and port forwarding
- ✅ Test container-to-container communication
- ✅ Use Docker's built-in DNS for container name resolution
- ✅ Compare different network modes (bridge, host, custom)
- ✅ Create custom networks with isolation
- ✅ Trace network traffic from host to container

### Understanding Docker Networking

Docker uses:
- **Network namespaces** - Isolation
- **Virtual ethernet pairs (veth)** - Connect containers to host
- **Linux bridge (docker0)** - Forward traffic between containers
- **iptables** - NAT and port forwarding
- **Built-in DNS** - Container name resolution

### Demo: Exploring Docker Networks

**Step 1: View host network interfaces BEFORE container**
```bash
# Count network interfaces
ip addr show | grep -E "^[0-9]+: " | wc -l

# List interface names
ip addr show | grep -E "^[0-9]+: " | awk '{print $2}'

# Check docker0 bridge
ip addr show docker0
```

**Step 2: List Docker networks**
```bash
# View default networks
docker network ls

# Inspect bridge network details
docker network inspect bridge
```

**Step 3: Start container and watch network changes**
```bash
# Start nginx container
docker run -d --name net-demo nginx:alpine

# Check network interfaces again (new veth pair created)
ip addr show | grep -E "^[0-9]+: " | wc -l

# View container's IP
CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' net-demo)
echo "Container IP: $CONTAINER_IP"
```

**Step 4: Examine container's network namespace**
```bash
# Get container PID
CONTAINER_PID=$(docker inspect -f '{{.State.Pid}}' net-demo)

# Container's view of network interfaces
docker exec net-demo ip addr show

# Or use nsenter
nsenter -t $CONTAINER_PID -n ip addr show
```

**Step 5: Find veth pair on host**
```bash
# List all veth interfaces on host
ip link show | grep veth

# Show bridge connections
brctl show docker0

# Or using bridge command
bridge link show | grep docker0
```

**Step 6: Test connectivity**
```bash
# Ping container from host
ping -c 3 $CONTAINER_IP

# Trace route to container
traceroute $CONTAINER_IP
```

**Step 7: Examine iptables rules**
```bash
# View Docker's NAT rules
sudo iptables -t nat -L DOCKER -n --line-numbers

# View port forwarding rules
sudo iptables -t nat -L POSTROUTING -n | grep docker
```

**Step 8: Start container with port mapping**
```bash
# Map host port 8080 to container port 80
docker run -d --name net-demo-port -p 8080:80 nginx:alpine

# View the iptables rule created for port mapping
sudo iptables -t nat -L DOCKER -n | grep 8080

# Test port forwarding
curl -s http://localhost:8080 | head -5
```

**Step 9: Create custom network**
```bash
# Create custom bridge network
docker network create --driver bridge demo-network

# Inspect the new network
docker network inspect demo-network | jq '.[0] | {Name, Subnet: .IPAM.Config[0].Subnet}'
```

**Step 10: Container-to-container communication**
```bash
# Start two containers in custom network
docker run -d --name app1 --network demo-network nginx:alpine
docker run -d --name app2 --network demo-network nginx:alpine

# Test connectivity using container names (DNS)
docker exec app1 ping -c 3 app2

# Docker provides built-in DNS for name resolution!
```

**Step 11: Compare network modes**
```bash
# Host mode - container shares host's network namespace
docker run -d --name net-host --network host nginx:alpine

# Check namespace (should be same as host)
HOST_PID=$(docker inspect -f '{{.State.Pid}}' net-host)
ls -la /proc/$HOST_PID/ns/net
ls -la /proc/1/ns/net
# Same inode = same namespace

# Cleanup
docker stop net-host
docker rm net-host
```

**Step 12: View network namespaces**
```bash
# Container network namespace location
echo "Container net namespace: /proc/$CONTAINER_PID/ns/net"
readlink /proc/$CONTAINER_PID/ns/net

# Network statistics for container
docker exec net-demo cat /proc/net/dev
```

**Cleanup:**
```bash
docker stop net-demo net-demo-port app1 app2
docker rm net-demo net-demo-port app1 app2
docker network rm demo-network
```

---

## ⚙️ Part 5: Process Isolation

The big reveal: containers are just isolated processes!

### 🎯 What You'll Achieve

By the end of this section, you will:
- ✅ **Prove** that containers are just regular Linux processes
- ✅ Find container processes in the host's process table
- ✅ View the process hierarchy and parent-child relationships
- ✅ Compare process views from inside vs outside the container
- ✅ Access container process information via `/proc/<PID>/`
- ✅ Kill a container by killing its host process
- ✅ Monitor CPU and memory usage from the host perspective
- ✅ Send signals to container processes
- ✅ Understand that containers use real host resources (no virtualization)
- ✅ See multiple containers as multiple processes on the same kernel

### Understanding Process Isolation

- Containers are **NOT virtual machines**
- They are **regular Linux processes** with isolation
- They run directly on the **host kernel**
- They use **host CPU, memory, and I/O**
- Isolation comes from **namespaces and cgroups**

### Demo: Containers as Processes

**Step 1: Start a container**
```bash
# Start nginx container
docker run -d --name process-demo nginx:alpine
```

**Step 2: Find container process on host**
```bash
# Get container's main process PID
CONTAINER_PID=$(docker inspect -f '{{.State.Pid}}' process-demo)
echo "Main container process PID: $CONTAINER_PID"

# View it in host process table
ps aux | grep $CONTAINER_PID | grep -v grep

# It's just a regular process!
```

**Step 3: View process tree**
```bash
# Show process hierarchy
pstree -p $CONTAINER_PID

# Or using ps
ps --forest -p $CONTAINER_PID

# Container process is part of host's process tree
```

**Step 4: View all container processes**
```bash
# Processes from container's perspective (PID namespace)
docker exec process-demo ps aux

# Same processes from host's perspective
ps aux | grep nginx | grep -v grep
```

**Step 5: Examine process details**
```bash
# Command line
cat /proc/$CONTAINER_PID/cmdline | tr '\0' ' '
echo

# Environment variables
cat /proc/$CONTAINER_PID/environ | tr '\0' '\n' | head -10

# Resource limits
cat /proc/$CONTAINER_PID/limits
```

**Step 6: Find parent process**
```bash
# Get parent PID
PARENT_PID=$(ps -o ppid= -p $CONTAINER_PID | tr -d ' ')
echo "Container PID: $CONTAINER_PID"
echo "Parent PID: $PARENT_PID"

# View parent (usually dockerd or containerd)
ps aux | grep $PARENT_PID | grep -v grep
```

**Step 7: Start multiple containers**
```bash
# Start 3 more containers
docker run -d --name proc-demo-1 nginx:alpine
docker run -d --name proc-demo-2 nginx:alpine
docker run -d --name proc-demo-3 nginx:alpine

# View all their PIDs
for container in process-demo proc-demo-1 proc-demo-2 proc-demo-3; do
    pid=$(docker inspect -f '{{.State.Pid}}' $container)
    echo "$container: PID $pid"
done

# All nginx processes on host
ps aux | grep nginx | grep -v grep
```

**Step 8: Kill container from host**
```bash
# Get PID of one container
PID_TO_KILL=$(docker inspect -f '{{.State.Pid}}' proc-demo-1)
echo "Killing container with PID: $PID_TO_KILL"

# Kill it using regular kill command
kill $PID_TO_KILL
sleep 2

# Docker detected the process died
docker ps -a | grep proc-demo-1
```

**Step 9: Monitor CPU usage**
```bash
# View CPU usage from Docker
docker stats --no-stream process-demo

# View from /proc filesystem
cat /proc/$CONTAINER_PID/status | grep -E "VmRSS|VmSize"

# It's consuming real host resources!
```

**Step 10: View open file descriptors**
```bash
# List file descriptors
ls -l /proc/$CONTAINER_PID/fd/ | head -10

# These are real file descriptors on the host system
```

**Step 11: Send signals to container**
```bash
# Send SIGHUP signal
kill -HUP $CONTAINER_PID

# Container handles it gracefully
docker ps | grep process-demo

# We can control it like any other process!
```

**Step 12: Compare with host process**
```bash
# Host process (PID 1) namespaces
echo "Host (PID 1) namespaces:"
ls -la /proc/1/ns/

# Container process namespaces
echo "Container (PID $CONTAINER_PID) namespaces:"
ls -la /proc/$CONTAINER_PID/ns/

# Different namespace inodes = isolation
# But both are processes on the same kernel!
```

**Cleanup:**
```bash
docker stop process-demo proc-demo-2 proc-demo-3
docker rm process-demo proc-demo-2 proc-demo-3
```

---

## 🔑 Key Takeaways

### The Container Formula

```
Container = Process + Namespaces + Cgroups + Filesystem Layers
```

### What We Learned

1. **Namespaces** provide isolation
   - PID, Network, Mount, UTS, IPC, User
   - Each container gets its own namespaces
   - Makes processes think they're alone

2. **Cgroups** control resources
   - Limit CPU, memory, I/O
   - Enforced by the kernel
   - Prevent container resource hogging

3. **OverlayFS** manages storage
   - Read-only image layers
   - Writable container layer
   - Copy-on-Write optimization
   - Efficient layer sharing

4. **Networking** enables communication
   - veth pairs connect containers
   - Bridge forwards traffic
   - iptables handles NAT
   - Built-in DNS for names

5. **Processes** are the core
   - No virtualization involved
   - Direct kernel execution
   - Real host resources
   - Just isolated processes

### Why This Matters

- **Fast startup** - Milliseconds vs seconds for VMs
- **Efficient** - No hypervisor overhead
- **Lightweight** - Share host kernel
- **Portable** - Run anywhere Linux runs
- **Scalable** - Thousands of containers per host

---

## 📚 Additional Resources

### Official Documentation

**Kernel Features:**
- [Linux Namespaces Man Page](https://man7.org/linux/man-pages/man7/namespaces.7.html) - Complete namespace reference
- [PID Namespaces](https://man7.org/linux/man-pages/man7/pid_namespaces.7.html) - Process isolation details
- [Network Namespaces](https://man7.org/linux/man-pages/man7/network_namespaces.7.html) - Network isolation
- [Mount Namespaces](https://man7.org/linux/man-pages/man7/mount_namespaces.7.html) - Filesystem isolation
- [Control Groups v2](https://www.kernel.org/doc/html/latest/admin-guide/cgroup-v2.html) - Complete cgroups guide
- [OverlayFS Documentation](https://www.kernel.org/doc/html/latest/filesystems/overlayfs.html) - Union filesystem details

**Docker Specific:**
- [Docker Architecture](https://docs.docker.com/get-started/overview/) - High-level overview
- [Docker Storage Drivers](https://docs.docker.com/storage/storagedriver/) - Filesystem management
- [Docker Networking](https://docs.docker.com/network/) - Network configuration
- [Understanding Image Layers](https://docs.docker.com/build/guide/layers/) - Layer optimization
- [Docker Runtime Options](https://docs.docker.com/engine/reference/run/) - Complete run reference

**Red Hat / Rocky Linux:**
- [RHEL Cgroups Guide](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/managing_monitoring_and_updating_the_kernel/assembly_using-cgroups-v2-to-control-distribution-of-cpu-time-for-applications_managing-monitoring-and-updating-the-kernel)
- [Container Tools on RHEL](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/building_running_and_managing_containers/)
- [Rocky Linux Documentation](https://docs.rockylinux.org/)

### Tools
- `nsenter` - [Enter namespaces](https://man7.org/linux/man-pages/man1/nsenter.1.html)
- `unshare` - [Create new namespaces](https://man7.org/linux/man-pages/man1/unshare.1.html)
- `lsns` - [List namespaces](https://man7.org/linux/man-pages/man8/lsns.8.html)
- `cgget` / `cgset` - [Cgroup management tools](https://linux.die.net/man/1/cgget)
- `brctl` - [Bridge management](https://linux.die.net/man/8/brctl)
- `ip netns` - [Network namespace management](https://man7.org/linux/man-pages/man8/ip-netns.8.html)
- `systemd-cgls` - [View cgroup hierarchy](https://www.freedesktop.org/software/systemd/man/systemd-cgls.html)

### Further Exploration Topics

**Container Runtimes:**
- [runc](https://github.com/opencontainers/runc) - Reference OCI runtime
- [containerd](https://containerd.io/) - Industry-standard container runtime
- [cri-o](https://cri-o.io/) - Kubernetes-native runtime
- [Podman](https://podman.io/) - Daemonless container engine

**Security:**
- [seccomp](https://www.kernel.org/doc/html/latest/userspace-api/seccomp_filter.html) - System call filtering
- [AppArmor](https://apparmor.net/) - Mandatory access control
- [SELinux](https://github.com/SELinuxProject/selinux/wiki) - Security enhanced Linux
- [Linux Capabilities](https://man7.org/linux/man-pages/man7/capabilities.7.html) - Fine-grained privileges

**Orchestration:**
- [Kubernetes](https://kubernetes.io/docs/concepts/) - Container orchestration
- [Docker Swarm](https://docs.docker.com/engine/swarm/) - Docker's native clustering
- [Docker Compose](https://docs.docker.com/compose/) - Multi-container applications

**Standards:**
- [OCI Runtime Specification](https://github.com/opencontainers/runtime-spec) - Container runtime standards
- [OCI Image Specification](https://github.com/opencontainers/image-spec) - Container image format
- [Container Network Interface (CNI)](https://github.com/containernetworking/cni) - Network plugin interface

### Books & Courses

- **"Docker Deep Dive" by Nigel Poulton** - Comprehensive Docker guide
- **"Container Security" by Liz Rice** - Security best practices
- **"Kubernetes Patterns" by Bilgin Ibryam** - Design patterns for containers
- **Linux Kernel Development by Robert Love** - Understanding kernel internals

### Videos & Talks

- [Containers From Scratch](https://www.youtube.com/watch?v=8fi7uSYlOdc) - Liz Rice (must watch!)
- [Docker Internals](https://www.youtube.com/watch?v=sK5i-N34im8) - Jerome Petazzoni
- [Understanding Linux Containers](https://www.youtube.com/watch?v=el7768BNUPw) - Various speakers

### Hands-On Practice

- Try building containers without Docker using only Linux primitives
- Experiment with different cgroup settings and observe behavior
- Create custom namespace configurations
- Build minimal container images
- Explore container security hardening

---

## 🧹 Clean Up Everything

After completing all demos:

```bash
# Stop all running containers
docker stop $(docker ps -aq)

# Remove all containers
docker rm $(docker ps -aq)

# Remove all images
docker rmi $(docker images -q)

# Remove all volumes
docker volume prune -f

# Remove all networks
docker network prune -f

# Clean everything
docker system prune -a --volumes -f

# Verify clean state
docker ps -a
docker images
docker volume ls
docker network ls
```

---

## 🎬 YouTube Video Structure

### Suggested Flow (30-45 minutes)

1. **Introduction** (2-3 min)
   - What are containers really?
   - Not VMs - just isolated processes

2. **Namespaces** (8-10 min)
   - PID isolation demo
   - Network isolation demo
   - Show namespace inodes

3. **Cgroups** (6-8 min)
   - Memory limits demo
   - CPU limits demo
   - OOM killer in action

4. **Filesystem** (8-10 min)
   - Image layers
   - Copy-on-Write
   - Layer sharing

5. **Networking** (6-8 min)
   - veth pairs
   - Docker bridge
   - Port mapping

6. **Processes** (5-7 min)
   - Container as process
   - Kill from host
   - Multiple containers

7. **Wrap-up** (2-3 min)
   - The container formula
   - Key takeaways

---

## 🐛 Troubleshooting

### Common Issues

**Docker not starting:**
```bash
sudo systemctl status docker
sudo journalctl -u docker.service -n 50
sudo systemctl restart docker
```

**Permission denied:**
```bash
sudo usermod -aG docker $USER
newgrp docker
```

**Cgroup errors:**
```bash
# Check cgroup version
cat /proc/cgroups
mount | grep cgroup
```

**Network bridge issues:**
```bash
ip link show docker0
sudo systemctl restart docker
```

**SELinux blocking:**
```bash
getenforce
sudo setenforce 0  # Temporary
```

---

Made with ❤️ for understanding Docker internals on Rocky Linux

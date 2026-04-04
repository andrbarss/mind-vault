# WSL Connection Issues - Troubleshooting Guide

## Quick Diagnostics

Run the diagnostic script:
```bash
./tools/wsl_diagnostics.sh
```

This will show:
- System information (WSL version, uptime, boot ID)
- Network configuration (DNS, interfaces)
- System resources (memory, load)
- Recent kernel messages
- Connection tests
- WSL configuration

## Common Causes

### 1. Windows Updates
Windows updates can restart WSL2 VM or change network configuration.

**Symptoms**:
- WSL becomes unresponsive
- Network connectivity lost
- DNS resolution fails

**Check**:
```bash
# From WSL
./tools/wsl_diagnostics.sh

# From Windows PowerShell
wsl --status
Get-EventLog -LogName System -Source Microsoft-Windows-WSL -Newest 10
```

**Fix**:
```powershell
# From Windows PowerShell
wsl --shutdown
wsl --distribution Ubuntu  # or your distro name
```

### 2. Windows Sleep/Hibernate
Windows sleep/hibernate can disconnect WSL network stack.

**Symptoms**:
- Network unreachable after Windows wakes
- DNS resolution fails
- Can't connect to external services

**Check**:
```bash
# From WSL
ping -c 1 github.com
ping -c 1 8.8.8.8
```

**Fix**:
```powershell
# From Windows PowerShell
wsl --shutdown
wsl
```

### 3. Network Adapter Changes
Windows network adapter changes (VPN, WiFi switching, etc.) affect WSL networking.

**Symptoms**:
- Network connectivity lost
- DNS resolution fails
- IP address changes

**Check**:
```bash
# From WSL
cat /etc/resolv.conf
ip addr show
```

**Fix**:
```bash
# From WSL - restart network
sudo service networking restart

# Or from Windows PowerShell
wsl --shutdown
wsl
```

### 4. WSL2 VM Issues
WSL2 runs in a lightweight VM that can have issues.

**Symptoms**:
- WSL completely unresponsive
- Processes hang
- System becomes slow

**Check**:
```powershell
# From Windows PowerShell
wsl --status
wsl --list --verbose
```

**Fix**:
```powershell
# From Windows PowerShell - full restart
wsl --shutdown
# Wait a few seconds
wsl
```

### 5. Resource Exhaustion
WSL2 VM may run out of memory or other resources.

**Symptoms**:
- System becomes slow
- Processes killed (OOM)
- High load average

**Check**:
```bash
# From WSL
free -h
uptime
dmesg | grep -i "out of memory"
```

**Fix**:
- Close unnecessary applications
- Restart WSL: `wsl --shutdown` (from Windows)
- Adjust WSL memory limit in `.wslconfig` (Windows user home)

## Windows-Side Diagnostics

### PowerShell Commands

**Check WSL Status**:
```powershell
wsl --status
wsl --list --verbose
```

**Check WSL Events**:
```powershell
Get-EventLog -LogName System -Source Microsoft-Windows-WSL -Newest 20
```

**Check WSL Network**:
```powershell
Get-NetAdapter | Where-Object {$_.InterfaceDescription -like "*WSL*"}
```

**Check WSL Processes**:
```powershell
Get-Process | Where-Object {$_.ProcessName -like "*wsl*"}
```

### Windows Event Viewer

1. Open Event Viewer (`eventvwr.msc`)
2. Navigate to: **Windows Logs** → **System**
3. Filter by Source: `Microsoft-Windows-WSL`
4. Look for errors or warnings around the time of the issue

## WSL Configuration

### `/etc/wsl.conf`

Current configuration:
```ini
[boot]
systemd=true
```

To prevent DNS auto-generation issues:
```ini
[network]
generateResolvConf = false
```

Then manually configure `/etc/resolv.conf`:
```
nameserver 8.8.8.8
nameserver 8.8.4.4
```

### Windows `.wslconfig`

Location: `C:\Users\<YourUsername>\.wslconfig`

Example:
```ini
[wsl2]
memory=8GB
processors=4
swap=2GB
localhostForwarding=true
```

## Monitoring Tools

### Real-time Monitoring

**Network connectivity**:
```bash
watch -n 1 'ping -c 1 github.com && echo "OK" || echo "FAIL"'
```

**System resources**:
```bash
watch -n 1 'free -h && uptime'
```

**WSL processes**:
```bash
watch -n 1 'ps aux | grep -E "(wsl|init)" | head -10'
```

### Log Monitoring

**Kernel messages**:
```bash
dmesg -w  # Watch for new messages
```

**System logs**:
```bash
journalctl -f  # If systemd is enabled
```

## Prevention

1. **Keep WSL updated**:
   ```bash
   sudo apt update && sudo apt upgrade
   ```

2. **Keep Windows updated** (but be aware updates can affect WSL)

3. **Configure WSL to survive Windows restarts**:
   - Set WSL to start automatically
   - Use `.wslconfig` to limit resource usage

4. **Monitor WSL health**:
   - Run `./tools/wsl_diagnostics.sh` periodically
   - Check Windows Event Viewer for WSL errors

## Quick Recovery

If WSL becomes unresponsive:

1. **From Windows PowerShell**:
   ```powershell
   wsl --shutdown
   # Wait 5-10 seconds
   wsl
   ```

2. **If that doesn't work**:
   ```powershell
   # Check for stuck processes
   Get-Process | Where-Object {$_.ProcessName -like "*wsl*"}
   
   # Force shutdown
   wsl --terminate Ubuntu  # or your distro
   wsl --shutdown
   ```

3. **If still not working**:
   - Restart Windows
   - Check Windows Event Viewer for errors
   - Check WSL version: `wsl --status`

## References

- [WSL Documentation](https://docs.microsoft.com/en-us/windows/wsl/)
- [WSL GitHub Issues](https://github.com/microsoft/WSL/issues)
- [WSL2 Networking](https://docs.microsoft.com/en-us/windows/wsl/networking)


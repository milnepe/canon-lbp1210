# Canon LBP-1210 printer drivers fixed for Debian 13 (Trixie)

Concise installation instructions for Canon's legacy CAPT Linux driver, local USB printing, automatic startup, and a remote Linux IPP Everywhere client.

## 1. Obtain the Canon packages

Use Canon's legacy packages:

```text
cndrvcups-common_3.21-1_amd64.deb
cndrvcups-capt_2.71-1_amd64.deb
```

Put both original `.deb` files in one directory. The accompanying `canon-build-packages.sh` rebuilds their dependency metadata for Trixie.

## 2. Install prerequisites and 32-bit support

The Canon CAPT filter and `captmon` are 32-bit programs.

```bash
apt update
apt install cups dpkg-dev libc6 libglib2.0-0 libstdc++6 ghostscript \
            libpopt0 libxml2 zlib1g libcups2t64 libatk1.0-0t64

dpkg --add-architecture i386
apt update
apt install libpopt0:i386 libxml2:i386
```

`libpopt0:i386` is required by `captfilter`; `libxml2:i386` is required by `captmon`.

## 3. Rebuild the Canon packages

Run the supplied build script as root in the directory containing the original Canon packages:

```bash
chmod +x canon-build-packages.sh
./canon-build-packages.sh
```

It extracts each package, changes only the Debian dependency metadata, and rebuilds:

```text
cndrvcups-common_3.21-1_amd64-fixed.deb
cndrvcups-capt_2.71-1_amd64-fixed.deb
```

The common package removes obsolete GTK/libglade/old-CUPS dependencies. The CAPT package removes obsolete `libgcc1`, GTK/libglade dependencies and changes `libatk1.0-0` to `libatk1.0-0t64`.

## 4. Check CUPS is running

```bash
systemctl status cups
```

## 5. Install the fixed packages

```bash
apt install ./cndrvcups-common_3.21-1_amd64-fixed.deb \
            ./cndrvcups-capt_2.71-1_amd64-fixed.deb
```

Verify the 32-bit Canon programs:

```bash
ldd /usr/bin/captfilter
ldd /usr/bin/captmon
```

There must be no `=> not found` entries.

A direct `captfilter` test may wait for input; `Ctrl-C` is normal.

## 6. Connect and identify the printer

```bash
lsusb
...
Bus 001 Device 004: ID 04a9:2617 Canon, Inc. LBP1210
...
```
```bash
ls -l /dev/usb/lp0
crw-rw---- 1 root lp 180, 0 Sep 14 12:56 /dev/usb/lp0
```
```bash
/usr/sbin/lpinfo -v
file cups-brf:/
network ipps
network beh
network lpd
direct ccp
network socket
network http
network ipp
serial serial:/dev/ttyS0?baud=115200
serial serial:/dev/ttyS1?baud=115200
network https
direct parallel:/dev/lp0
direct usb://Canon/LASER%20SHOT%20LBP-1210?serial=012B2JZA
```

## 7. Restart CUPS

```bash
systemctl restart cups
```

## 8. Create the CUPS queue

The CAPT package installs this English PPD:

```text
/usr/share/cups/model/CNCUPSLBP1210CAPTK.ppd
```

Create the queue:

```bash
/usr/sbin/lpadmin -p LBP1210 -E \
  -v ccp:/var/ccpd/fifo0 \
  -P /usr/share/cups/model/CNCUPSLBP1210CAPTK.ppd

/usr/sbin/lpadmin -d LBP1210
```

The physical printer's queue must use `ccp:/var/ccpd/fifo0`.

## 9. Configure CCPD

Configure the printer:

```bash
/usr/sbin/ccpdadmin -p LBP1210 -o /dev/usb/lp0
```

The configuration should be updated.

```bash
cat /etc/ccpd.conf
# Canon Printer Daemon for CUPS Configuration Data

<Path>
# CUPS configuration file path.
#  Default  /etc/cups/

CUPS_ConfigPath   /etc/cups/

# Log directory path.
#  LogDirectoryPath /var/log/CCPD/

</Path>

<Printer LBP1210>
DevicePath /dev/usb/lp0
</Printer>

<Ports>
# Status monitoring socket port.
#  Default 59787
UI_Port  59787
PDATA_Port  59687
</Ports>
```

The configuration should associate `LBP1210` with `/dev/usb/lp0`.
```bash
/usr/sbin/ccpdadmin -x

 CUPS_ConfigPath = /etc/cups/
 LOG Path        = None
 UI Port         = 59787

 Entry Num  : Spooler	: Backend	: FIFO path		: Device Path 	: Status 
 ----------------------------------------------------------------------------
     [0]    : LBP1210 	: ccp 		: /var/ccpd/fifo0 	: /dev/usb/lp0 	:
```

## 10. Make the Canon init script Trixie-safe

The old Canon `/etc/init.d/ccpd` script calls `start-stop-daemon` but does not guarantee `/sbin` and `/usr/sbin` are in `PATH`.

Back it up:

```bash
cp -a /etc/init.d/ccpd /etc/init.d/ccpd.bak
```

Set its PATH line to:

```text
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
```

For example:

```bash
sed -i 's|^export PATH=.*|export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin|' /etc/init.d/ccpd
```

## 11. Configure automatic startup with systemd

The Canon SysV script has no usable runlevel metadata on Trixie, so `update-rc.d ccpd defaults` fails. Use a separate native systemd unit.

Create `/etc/systemd/system/canon-ccpd.service`:

```ini
[Unit]
Description=Canon Printer Daemon for CUPS
After=cups.service
Requires=cups.service

[Service]
Type=forking
ExecStart=/etc/init.d/ccpd start
ExecStop=/etc/init.d/ccpd stop
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

Enable it:

```bash
systemctl daemon-reload
systemctl enable canon-ccpd.service
systemctl is-enabled canon-ccpd.service
```

Expected:

```text
enabled
```

Do not enable the generated `ccpd.service`; use `canon-ccpd.service`.

## 12. Reboot print server
```bash
/sbin/reboot
```

## 13. Test local printing

```bash
echo "Canon LBP-1210 test" | lp -d LBP1210
```

Check:

```bash
lpstat -p LBP1210
lpstat -W not-completed -o
lpstat -W completed -o | tail
```

A completed job that physically prints confirms the local CUPS → CCPD → CAPT → USB path.

## 14. Share the printer through CUPS

On the Debian print server:

```bash
/usr/sbin/cupsctl --share-printers --remote-any
/usr/sbin/lpadmin -h localhost:631 -p LBP1210 -o printer-is-shared=true
```

Check:

```bash
ss -lntp | grep ':631'
```

If a firewall is enabled, allow TCP port 631 from the LAN.

## 15. Configure a remote Ubuntu/Linux client

The Canon driver is not required on the remote client. It only needs CUPS and an IPP Everywhere queue.

Install CUPS if necessary:

```bash
sudo apt install cups
```

Verify that the server is reachable:

```bash
ping -c 2 gigabyte
lpstat -h gigabyte:631 -v
```

The server-side queue should report:

```text
device for LBP1210: ccp:/var/ccpd/fifo0
```

Create a separate client queue:

```bash
sudo lpadmin -p LBP1210_gigabyte \
  -E \
  -v ipp://gigabyte:631/printers/LBP1210 \
  -m everywhere
```

Make it the default:

```bash
sudo lpadmin -d LBP1210_gigabyte
```

Verify:

```bash
lpstat -v
lpstat -p
lpstat -d
```

The new client queue should show:

```text
device for LBP1210_gigabyte: ipp://gigabyte:631/printers/LBP1210
```

Test:

```bash
echo "Remote IPP test" | lp
```

An old queue can be left untouched as a fallback, for example:

```text
LBP1210 -> ipp://cooker:631/printers/LBP1210
```

while `LBP1210_gigabyte` is the default.

## 16. Useful troubleshooting checks

If a job completes but does not print, first check on print server as su:

```bash
ldd /usr/bin/captfilter
ldd /usr/bin/captmon
ps -ef | grep -E '[c]cpd|[c]aptmon'
lsof /dev/usb/lp0
tail -100 /var/log/cups/error_log
```

`captfilter` and `captmon` must have all 32-bit libraries resolved. A healthy running configuration has CCPD and `captmon` sharing `/dev/usb/lp0`.

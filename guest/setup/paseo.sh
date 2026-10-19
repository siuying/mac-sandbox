#!/bin/zsh -l
# Paseo daemon, started at login on 127.0.0.1:6767 (add the VM in Paseo as ssh://VM). Install paseo via mise.toml.
set -euxo pipefail

mkdir -p ~/.mac-sandbox ~/Library/LaunchAgents ~/Library/Logs
cat > ~/.mac-sandbox/paseo-daemon.sh <<'SCRIPT'
#!/bin/zsh -l
exec paseo daemon run
SCRIPT
chmod +x ~/.mac-sandbox/paseo-daemon.sh

cat > ~/Library/LaunchAgents/com.mac-sandbox.paseo.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.mac-sandbox.paseo</string>
  <key>ProgramArguments</key><array><string>$HOME/.mac-sandbox/paseo-daemon.sh</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>StandardOutPath</key><string>$HOME/Library/Logs/paseo-daemon.log</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/paseo-daemon.log</string>
</dict>
</plist>
PLIST

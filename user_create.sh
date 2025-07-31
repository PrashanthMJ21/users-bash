#!/bin/bash

# STEP 0: Slack Webhook Setup
WEBHOOK_URL="https://hooks.slack.com/services/XXXXX/YYYYY/ZZZZZ"  # Replace with your actual Slack webhook

# STEP 1: Install and start auditd (only if not already installed)
if ! dpkg -s auditd &>/dev/null; then
    sudo apt update -y
    sudo apt install auditd audispd-plugins -y
    sudo systemctl enable auditd
    sudo systemctl start auditd
fi

# STEP 2: Create users and set passwords
declare -A users
users=( ["user1"]="pass01" ["user2"]="pass02" ["user3"]="pass03" )

for username in "${!users[@]}"; do
    if ! id "$username" &>/dev/null; then
        sudo useradd -m "$username"
    fi
    echo "$username:${users[$username]}" | sudo chpasswd || echo "❌ Failed to set password for $username"
    sudo deluser "$username" sudo &>/dev/null
done

# STEP 3: Protect audit logs
sudo chmod 600 /var/log/audit/audit.log
sudo chown root:root /var/log/audit/audit.log

# STEP 4: Flush existing audit rules
sudo auditctl -D

# STEP 5: Add audit rules for each user
for username in "${!users[@]}"; do
    if id "$username" &>/dev/null; then
        USER_UID=$(id -u "$username")

        # 64-bit syscalls
        sudo auditctl -a always,exit -F arch=b64 -F euid=$USER_UID -S execve -k ${username}-exec
        sudo auditctl -a always,exit -F arch=b64 -F euid=$USER_UID -S creat,open,openat -k ${username}-create
        sudo auditctl -a always,exit -F arch=b64 -F euid=$USER_UID -S unlink,unlinkat,rmdir -k ${username}-delete
        sudo auditctl -a always,exit -F arch=b64 -F euid=$USER_UID -S chmod,fchmod,fchmodat,chown,fchown,lchown,fchownat -k ${username}-perms

        # 32-bit syscalls (for completeness)
        sudo auditctl -a always,exit -F arch=b32 -F euid=$USER_UID -S execve -k ${username}-exec
        sudo auditctl -a always,exit -F arch=b32 -F euid=$USER_UID -S creat,open,openat -k ${username}-create
        sudo auditctl -a always,exit -F arch=b32 -F euid=$USER_UID -S unlink,unlinkat,rmdir -k ${username}-delete
        sudo auditctl -a always,exit -F arch=b32 -F euid=$USER_UID -S chmod,fchmod,fchmodat,chown,fchown,lchown,fchownat -k ${username}-perms
    fi
done

# STEP 6: Delete users who have not logged in for 90 days
for username in "${!users[@]}"; do
    if id "$username" &>/dev/null; then
        INACTIVE_DAYS=$(sudo lastlog -u "$username" | awk 'NR==2 {print $(NF)}')
        if [[ "$INACTIVE_DAYS" =~ ^[0-9]+$ ]] && [ "$INACTIVE_DAYS" -ge 90 ]; then
            echo "Deleting user $username (inactive for $INACTIVE_DAYS days)"
            sudo userdel -r "$username"
        fi
    fi
done

# STEP 7: Expire password every 180 days (6 months) and lock account after expiry
for username in "${!users[@]}"; do
    if id "$username" &>/dev/null; then
        sudo chage -M 180 -I 0 "$username"
    fi
done

# STEP 8: Create password expiration notifier script
NOTIFIER_SCRIPT="/usr/local/bin/password_expiry_notifier.sh"

sudo tee "$NOTIFIER_SCRIPT" > /dev/null <<EOF
#!/bin/bash
users=(user1 user2 user3)
today=\$(date +%s)

for user in "\${users[@]}"; do
    exp_date=\$(chage -l "\$user" | grep "Password expires" | cut -d: -f2- | xargs)
    if [[ "\$exp_date" == "never" || -z "\$exp_date" ]]; then continue; fi

    exp_sec=\$(date -d "\$exp_date" +%s 2>/dev/null)

    if [[ "\$exp_sec" -lt "\$today" ]]; then
        curl -s -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\":lock: *ALERT*: Password for user *\$user* has expired and they are locked out. Admin action required.\"}" "$WEBHOOK_URL"
    fi
done
EOF

sudo chmod +x "$NOTIFIER_SCRIPT"

# STEP 9: Register cronjob to check expired passwords daily at 9 AM
cron_entry="0 9 * * * $NOTIFIER_SCRIPT"
( sudo crontab -l 2>/dev/null | grep -v "$NOTIFIER_SCRIPT" ; echo "$cron_entry" ) | sudo crontab -

# STEP 10: Setup audit log rotation (monthly, keep 3 months, secure permissions)
sudo tee /etc/logrotate.d/audit > /dev/null <<EOF
/var/log/audit/audit.log {
    monthly                # rotate once a month
    rotate 3               # keep 3 months of logs
    missingok              # skip if file is missing
    notifempty             # skip if file is empty
    compress               # compress old logs
    delaycompress          # compress one cycle later
    create 0600 root root  # create new log with secure permissions
    postrotate
        /usr/sbin/service auditd restart > /dev/null
    endscript
}
EOF

echo "✅ All user management, audit, rotation, and notification setup completed."

#!/bin/bash
echo "======= USER ACTIVITY REPORT ======="

# --- Define monitored users ---
users=(user1 user2 user3)

# --- Step 1: List users and prompt ---
echo -e "\nAvailable users:"
for i in "${!users[@]}"; do
    echo "$((i+1)). ${users[$i]}"
done

read -p $'\nEnter the number of the user you want to check: ' user_choice
user=${users[$((user_choice-1))]}

if [ -z "$user" ]; then
    echo "❌ Invalid user selection"
    exit 1
fi

# --- Step 2: List activity types ---
echo -e "\nSelect activity to view:"
echo "1. Login/Logout Sessions"
echo "2. Sudo Attempts"
echo "3. File Deletions"
echo "4. File Access (Read/Write)"
echo "5. Command Executions"
echo "6. Permission Changes"

read -p $'\nEnter choice (1-6): ' choice
echo ""

# --- Step 3: Perform selected report ---
case $choice in
1)
    echo "--- Login/Logout Sessions for $user ---"
    sudo ausearch -m USER_LOGIN -i 2>/dev/null | awk -v user="$user" '
    /acct=/ && $0 ~ user {
        gsub("msg=audit\\(|\\)", "", $0)
        if ($0 ~ /op=login/)  printf("[%s %s IST] USER: %s logged in\n", $2, $3, user)
        if ($0 ~ /op=logout/) printf("[%s %s IST] USER: %s logged out\n", $2, $3, user)
    }'
    ;;
2)
    echo "--- Sudo Attempts for $user ---"
    sudo ausearch -m USER_CMD -i 2>/dev/null | awk -v user="$user" '
    $0 ~ user {
        gsub("msg=audit\\(|\\)", "", $0)
        match($0,/cmd=[^ ]+/); cmd=substr($0,RSTART,RLENGTH)
        printf("[%s %s IST] USER: %s ran %s\n", $2, $3, user, cmd)
    }'
    ;;
3)
    echo "--- File Deletions by $user ---"
    sudo ausearch -k ${user}-delete -i 2>/dev/null | awk -v user=$user '
    /name=/ {
        match($0, /name="[^"]+"/); fname=substr($0,RSTART,RLENGTH)
        printf("[%s %s IST] USER: %s deleted %s\n", $2, $3, user, fname)
    }'
    ;;
4)
    echo "--- File Access (Read/Write) by $user ---"
    sudo ausearch -k ${user}-create -i 2>/dev/null | awk -v user=$user '
    /name=/ {
        match($0, /name="[^"]+"/); fname=substr($0,RSTART,RLENGTH)
        printf("[%s %s IST] USER: %s opened %s\n", $2, $3, user, fname)
    }'
    ;;
5)
    echo "--- Commands Executed by $user ---"
    sudo ausearch -k ${user}-exec -i 2>/dev/null | awk -v user=$user '
    /a0=/ {
        cmd=$0
        sub(/.*a0=/, "", cmd)
        gsub(/ a[0-9]+=/, " ", cmd)
        printf("[%s %s IST] USER: %s ran command: %s\n", $2, $3, user, cmd)
    }'
    ;;
6)
    echo "--- Permission Changes by $user ---"
    sudo ausearch -k ${user}-perms -i 2>/dev/null | awk -v user=$user '
    /name=/ {
        match($0, /name="[^"]+"/); fname=substr($0,RSTART,RLENGTH)
        printf("[%s %s IST] USER: %s changed permissions on %s\n", $2, $3, user, fname)
    }'
    ;;
*)
    echo "❌ Invalid choice."
    ;;
esac

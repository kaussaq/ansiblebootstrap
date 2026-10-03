# bootstrap.sh

Uploads a specific public key, the one AWX will use, to one or more existing Linux hosts. On each host it creates a key-only SSH user with passwordless sudo.

Created to speed up onboarding multiple existing devices into a new AWX/Ansible instance. Some hosts can't be bootstrapped from Ansible on first contact (for example, Ubuntu 26.04's `sudo-rs` rewrites the sudo prompt, which broke privilege escalation for me on AWX). Your experience may differ. The script doesn't depend on sudo-rs and works on any host with standard sudo.

## What it does

For each host in `hosts.txt` it connects over SSH with an existing account, then:

1. Creates the new user (default `awx`) with a home directory and a locked password
2. Adds your public key to `~/.ssh/authorized_keys`
3. Installs `/etc/sudoers.d/<user>` with `NOPASSWD: ALL`, validated with `visudo -cf` first

It is safe to re-run. Existing users are left alone and the key is never added twice.

## Requirements

- Bash, OpenSSH client and `base64` on the machine running the script
- An existing account on each target that can log in over SSH and is either `root` or can use `sudo`
- The public key (`.pub`) that matches the private key in your AWX Machine Credential

## Usage

```bash
chmod +x bootstrap.sh
./bootstrap.sh [-u username] <public-key.pub>
```

| Option | Meaning |
| --- | --- |
| `-u username` | User to create. Defaults to `awx`. Lowercase letters, digits, `_` and `-` only. |
| `<public-key.pub>` | Public key to authorise. The first line of the file is used. |

```bash
./bootstrap.sh ~/.ssh/awx.pub              # creates "awx"
./bootstrap.sh -u ansible ~/.ssh/awx.pub   # creates "ansible"
```

## hosts.txt

Create `hosts.txt` in the same folder as the script. One `user@host` per line, where `user` is the **existing** account used to connect. Blank lines and lines starting with `#` are ignored.

```text
ubuntu@192.168.50.4
admin@192.168.50.5
root@192.168.50.6
# skipped
```

If the connecting user is `root`, `sudo` is not used. Otherwise the script runs with `sudo`.

## Passwords

**The existing account's password is prompted for on every host as the script runs.** You'll be asked for its SSH password and, for non-root users, its sudo password. Nothing is stored. If you already have key access to a host, SSH won't ask for a password.

## Verify

```bash
ssh -i ~/.ssh/<private-key> awx@<host> 'sudo -n whoami'
```

This should print `root` without prompting.

## Notes

- **Use a public key only.** The script rejects anything that doesn't look like one.
- **`example-key.pub`** is a placeholder showing the expected format. Use your own key.
- **`NOPASSWD: ALL` is full root access** for whoever holds the matching private key. Edit the sudoers line in the script to restrict it.
- **Locked password.** The account can only log in with the key. On hosts with `UsePAM no`, sshd rejects locked accounts. Replace `passwd -l` with `usermod -p '*'` there.
- **sshd restrictions.** `AllowUsers` or `AllowGroups` entries that exclude the new user will still block it. The script doesn't change sshd configuration.
- An existing `/etc/sudoers.d/<user>` file is overwritten.

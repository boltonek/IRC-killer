IRC Killer v2 - Script for terminating IRC processes


---

## Features

- Splits handling between IPv4 and IPv6, works via lsof
- Locks account after exceeding the limit n times
- Records statistics and writes logs

---
## Installation

```bash
# Build the application #

Upload the script to a folder /bin

check and irckiler

mkdir /usr/src/ircKiller

# Created users.db #

nano /etc/users.db

must contain only this  example:
root:1:1

This means that the root user will only have access to one IPv4 and one IPv6 connection in IRC

# Create permissions #

chmod 755 /bin/check
chmod 755 /bin/irckiler

# run the scripts in root
check

```
---
## Support

For support, please:

- Report issues on IRCnet /msg bolton

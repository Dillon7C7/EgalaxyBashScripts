# Egalaxy Multimedia Inc. Shell Scripts

This is a set of shell (mostly bash) scripts used for the daily workflow at Egalaxy Multimedia Inc.
All of the sensitive information (usernames, passwords, remote hosts, and remote directories) have been removed.
This repo is just a backup for myself; it isn't intended to be used by anyone else.


---

## Installation

- First, cd into the daily encoding work directory:

```shell
$ cd /home/encoder/w
```

- Then, clone this repo, cd into the newly created directory, and copy whatever is needed:

> optional: backup existing file(s) before copying

```shell
$ cp EXAMPLE_FILE EXAMPLE_FILE.back
$ git clone git://github.com/Dillon7C7/EgalaxyBashScripts
$ cd EgalaxyBashScripts
$ cp EXAMPLE_FILE ..
```

- Finally, cd back into the work directory, and add the appropriate sensitive information to the script:

> it might be worthwhile to create scripts with the appropriate `sed` incantations to automate this

```shell
$ cd ..
$ vim EXAMPLE_FILE
```

---

## License

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
- **[GNU GPL v3](https://www.gnu.org/licenses/gpl-3.0)**
- Copyleft 2018-2019 © <a href="https://github.com/Dillon7C7" target="_blank">Dillon Dommer</a>.

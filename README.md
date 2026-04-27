# meta-nomountfs -  NoMountFS MetaModule

The official userspace manager, WebUI, and script execution environment for [NoMountFS](https://github.com/maxsteeel/NoMountFS).

This repository handles the frontend and bash scripts required to control the NoMountFS kernel module dynamically.

## Features

*  Instantly mount or unmount specific modules on the fly without rebooting the device.
*  Visually manage module priority. The lowest module in the list gets the highest priority (wins on file collisions).
*  Highly optimized `metamount.sh` and `metauninstall.sh` scripts that reconstruct the VFS `lowerdir` chain and perform safe lazy unmounts in milliseconds.

## Architecture & Structure

The repository is modularized into three main categories:

### 1. WebUI
* `index.html`: The core DOM structure.
* `styles.css`: Pure MD3 styling with responsive layouts, accordion-style expansion cards, and hardware-accelerated animations.
* `index.js`: The JavaScript logic handling shell execution bridges, state mapping, and drag-and-drop interactions.

### 2. Scripts
* `metamount.sh`: Handles the dynamic compilation of mount branches and injects them into the running NoMountFS instance.
* `metauninstall.sh`: A fast-path hook that safely ejects a module from the stack, rebuilds the active path list, and performs a live remount without dropping the physical partition.

### 3. Configuration
* `mount_order`: The persistent text file tracking user-defined module load priorities.


## Credits

*  [A7mdwassa](https://github.com/A7mdwassa): For create a first versions of this module.

## ⚖️ License

This project is licensed under the GNU General Public License v3.0 (GPL-3.0). See the source files for detailed copyright notices.
---
title: "Customising Ubuntu live ISOs with Docker"
lastmod: "2023-04-21"
date: "2020-06-07"
---

Ubuntu live ISOs are often used for installing Ubuntu, but can also be useful for a number of other cases, including pre-configured desktops with no persistence and custom ISOs for installation. Traditionally, these have been [created with chroots](https://help.ubuntu.com/community/LiveCDCustomizationFromScratch) and there are GUI tools like [Cubic](https://launchpad.net/cubic) that make this process easier.

This process doesn't have any built-in 'checkpointing' though, so it can be difficult to iterate and be confident that you're not creating a non-reproducible snowflake. One tool that does do this very well however, is Docker's [image building system](https://docs.docker.com/develop/develop-images/baseimages/). This article will go through how to use that system to create Ubuntu live ISOs.

## Requirements

To start, a Linux distro with [squashfs-tools-ng](https://github.com/AgentD/squashfs-tools-ng) binaries available is needed to extract and repack the disk image in the ISO. At the time of writing, Ubuntu 20.04 LTS is the earliest version of Ubuntu supported.

[Docker](https://docs.docker.com/engine/install/ubuntu/) is also needed, as are the following packages -

```sh
apt-get install p7zip-full grub2-common mtools xorriso squashfs-tools-ng jq
```

Finally, download a copy of the Ubuntu live ISO to be customised from https://ubuntu.com/download/desktop. (This process will likely also work for other Ubuntu editions like the server edition, but there are often better ways to deploy servers.)

## Creating the Docker base image

The ISO works by booting the Linux kernel, mounting a squashfs image and starting Ubuntu from that. Therefore we need to grab that squashfs image from the ISO and create a Docker base image from it.

Run the following command to extract the squashfs image from the ISO -

```sh
# UBUNTU_ISO_PATH=path to the Ubuntu live ISO downloaded earlier
7z e -o. "$UBUNTU_ISO_PATH" casper/filesystem.squashfs
```

Then import that squashfs image into Docker -

```sh
sqfs2tar filesystem.squashfs | sudo docker import - "ubuntulive:base"
```

This will take a few minutes to complete.

## Customising using a Dockerfile

Now that the squashfs image is available as an image in Docker, we can build a [Dockerfile](https://docs.docker.com/engine/reference/builder/) that modifies it.

```dockerfile
# in the previous section, we imported the squashfs image into Docker as 'ubuntulive:base'
FROM ubuntulive:base

# set environment variables so apt installs packages non-interactively
# these variables will only be set in Docker, not in the resultant image
ENV DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical

# make some modifications, e.g. install Google Chrome
RUN wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add -
RUN sh -c 'echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google-chrome.list'
RUN apt-get update
RUN apt-get install -y google-chrome-stable

# install packages needed to repack the ISO (we'll be using this image to repack itself)
# grub-pc-bin needed for BIOS support
# grub-egi-amd64-bin and grub-efi-amd64-signed for EFI support
# grub2-common, mtools and xorriso are needed to build the ISO, xorriso is in universe repository
RUN add-apt-repository "deb http://archive.ubuntu.com/ubuntu $(lsb_release -sc) universe"
RUN apt-get install -y grub2-common grub-pc-bin grub-efi-amd64-bin grub-efi-amd64-signed mtools xorriso

# delete obsolete packages and any temporary state
RUN apt-get autoremove -y && apt-get clean
RUN rm -rf \
    /tmp/* \
    /boot/* \
    /var/backups/* \
    /var/log/* \
    /var/run/* \
    /var/crash/* \
    /var/lib/apt/lists/* \
    ~/.bash_history
```

### Working with systems that use systemd-resolved

Newer Ubuntu versions, e.g. 22.04 LTS, use [systemd-resolved](https://www.freedesktop.org/software/systemd/man/systemd-resolved.service.html). For this to work, it symlinks its own resolv.conf over to `/etc/resolv.conf` to override the default DNS resolution mechanism.

However, Docker also uses the same override strategy to make DNS work within its execution environment. It does this by mounting its override file to `/etc/resolv.conf` as read-only, which unfortunately means there's no way to change it during the build or copy process. As a result, DNS will likely not work in any environment other than the Docker environment.

To work around this, a service needs to be added that restores systemd-resolved's resolv.conf configuration by symlinking it back over to `/etc/resolv.conf`. The following systemd service unit will do this -

```ini
[Unit]
Description=Restore systemd-resolved resolv.conf symlink
# This is needed because Docker bind-mounts /etc/resolv.conf so that file ends
# up in the image instead of what the systemd-resolved package configures.
Wants=systemd-resolved.service
Before=network.target

[Service]
Type=oneshot
ExecStart=ln -fsv /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

[Install]
WantedBy=multi-user.target
```

Save the above to a file named `restore-resolvconf-symlink.service` in the same directory as the Dockerfile, then add the following to the Dockerfile to include it into the image -

```dockerfile
# fix up the /etc/resolv.conf symlink that Docker force bind-mounts
COPY restore-resolvconf-symlink.service /etc/systemd/system/
RUN ln -s /etc/systemd/system/restore-resolvconf-symlink.service /etc/systemd/system/multi-user.target.wants
```

With this, every time the image is started, this service will restore systemd-resolved's resolv.conf to `/etc/resolv.conf`, before the network is configured and used by the system, ensuring all DNS requests will use systemd-resolved.

(Specifically, this tells the system to use systemd-resolved's stub resolver which has additional features like per-interface DNS configuration and caching. If this is causing issues, change `/run/systemd/resolve/stub-resolv.conf` to `/run/systemd/resolve/resolv.conf` in the service unit file above to bypass the stub resolver and go straight to the DNS servers configured in systemd-resolved.)

## Building the customised image

First off, run the following to exclude the squashfs image and ISO from your build context to save time -

```sh
echo "**/*.squashfs" >> .dockerignore
echo "**/*.iso" >> .dockerignore
```

Then, to build the customised image, run -

```sh
sudo docker build -t ubuntulive:image .
```

If you're not happy with the output or errors occur, amend your Dockerfile and run the above command again to retry. It is also possible to explore the image and/or test commands at any point by copying the last successful image ID in the `docker build` output and running an instance of it, i.e. `sudo docker run -it --rm IMAGE_ID /bin/bash`.

## Repacking the squashfs image

Once you're happy with the image and `docker build` successfully completes, it is time to extract and convert the Docker image back into a squashfs image.

```sh
# run an instance of the Docker image
CONTAINER_ID=$(sudo docker run -d ubuntulive:image /usr/bin/tail -f /dev/null)
# delete the auto-created .dockerenv marker file so it doesn't end up in the squashfs image
sudo docker exec "${CONTAINER_ID}" rm /.dockerenv
# extract the Docker image contents to a tarball
sudo docker cp "${CONTAINER_ID}:/" - > newfilesystem.tar
# get the package listing for installation from ISO
sudo docker exec "${CONTAINER_ID}" dpkg-query -W --showformat='${Package} ${Version}\n' > newfilesystem.manifest
# kill the container instance of the Docker image
sudo docker rm -f "${CONTAINER_ID}"
# convert the image tarball into a squashfs image
tar2sqfs --quiet newfilesystem.squashfs < newfilesystem.tar
```

## Repacking the ISO image

Now that we have the new squashfs image, it's time to repack the ISO image.

```sh
# create a directory to build the ISO from
mkdir iso

# this is the path to the Ubuntu live ISO downloaded earlier
UBUNTU_ISO_PATH=ubuntu_iso_path

# extract the contents of the ISO to the directory, except the original squashfs image
7z x '-xr!filesystem.squashfs' -oiso "$UBUNTU_ISO_PATH"

# extract the EFI binaries from the ISO, they reside in a separate partition
# this allows the custom ISO to work when Secure Boot is enabled
EFI_PARTITION_DATA="$(sfdisk --json "$UBUNTU_ISO_PATH" | jq '.partitiontable.partitions | map(select(.type == "C12A7328-F81F-11D2-BA4B-00A0C93EC93B"))[0]')"
EFI_PARTITION_START="$(echo "$EFI_PARTITION_DATA" | jq '.start')"
EFI_PARTITION_SIZE="$(echo "$EFI_PARTITION_DATA" | jq '.size')"
dd bs=512 "count=$EFI_PARTITION_SIZE" "skip=$EFI_PARTITION_START" "if=$UBUNTU_ISO_PATH" of=efi.img
# grub looks in both the separate partition and /efi.img for the EFI binaries,
# so writing the partition to /efi.img has the same effect
cp efi.img iso/

# copy our custom squashfs image and manifest into place
cp newfilesystem.squashfs iso/casper/filesystem.squashfs
stat --printf="%s" iso/casper/filesystem.squashfs > iso/casper/filesystem.size
cp newfilesystem.manifest iso/casper/filesystem.manifest

# update state files
(cd iso; find . -type f -print0 | xargs -0 md5sum | grep -v "\./md5sum.txt" > md5sum.txt)

# remove obsolete files
rm iso/casper/filesystem.squashfs.gpg

# build the ISO image using the image itself
sudo docker run \
    -it \
    --rm \
    -v "$(pwd):/app" \
    ubuntulive:image \
    grub-mkrescue -v -o /app/ubuntulive.iso /app/iso/ -- -volid UbuntuLive
```

That's it. The repacked custom Ubuntu live ISO can now be found in `./ubuntulive.iso`. Test it out by using [GNOME Boxes](https://help.gnome.org/users/gnome-boxes/stable/) or another VM tool, or turn it into a bootable USB drive using `dd` or a GUI tool like [balenaEtcher](https://www.balena.io/etcher/).

## Caveats

* I don't use these ISOs for installation, so I haven't tested that part of the functionality after customisation
* packages that interact with systemd during installation will fail as there is no systemd instance running in the Docker environment. This should only be a problem with non-standard packages; all Ubuntu/Debian packages handle this case properly
* the kernel image used to boot comes as part of the ISO and will not be updated from within the Dockerfile with this process (e.g. via `apt`). To update the kernel image, download a new Ubuntu live ISO then repeat all the steps, **including** recreating the Docker base image. If the Docker base image is not recreated, it may become out-of-sync with the kernel image version and the ISO will not boot

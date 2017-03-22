#!/bin/bash

# This script installs Dell OMSA 8.x (latest version when writing these words) on Debian Lenny. The hack consists on using Debian wheezy bootstrap, for service launching and om* commands using. 
#
# Based on this post : http://gloriousoblivion.blogspot.com/2010/12/running-dell-omsa-63-under-debian-lenny.html
# 
# Author : Germain MAURICE <ger***.***ice@linkfluence.net>
#
#####################################
# 2011/02/22 : Germain MAURICE : first version (specific to amd64)
# 2011/02/24 : Modified by: Mukarram Syed for i386
# 2011/02/25 : Germain MAURICE : keep apt-get to be more compliant and autodetect achitecture of Debian installation
#####################################

echo "Be sure you've purge or removed any previous installation of Dell OMSA, via sara.nl by example. Continue ? type 'Yes' to continue."
read ASW
if [[ $ASW != "Yes" ]]; then
	exit;
fi

ARCH=$(apt-config dump | sed -nr 's/APT::Architecture \"(\S+)\";/\1/p');

GPG_KEY_ID=1285491434D8786F
GPG_KEY_SERVER=pgpkeys.mit.edu

####
#    For more information please refer to : http://linux.dell.com/repo/community/deb/latest/
#    and to the linux-poweredge mailing list https://lists.us.dell.com/mailman/listinfo/linux-poweredge
#
#   Available packages :
#    srvadmin-all:Install all OMSA components
#    srvadmin-base:Install only base OMSA, no web server
#    srvadmin-rac4:Install components to manage the Dell Remote Access Card 4
#    srvadmin-rac5:Install components to manage the Dell Remote Access Card 5
#    srvadmin-idrac:Install components to manage iDRAC
#    srvadmin-webserver:Install Web Interface
#    srvadmin-storageservices:Install RAID Management 
#
## Specify here what packages you want to install
OMSA_PACKAGES="srvadmin-base srvadmin-storageservices srvadmin-rac5 srvadmin-webserver";


cat <<EOF > /etc/apt/sources.list.d/debian.wheezy.sources.list
deb http://mirrors.kernel.org/debian/ wheezy main non-free contrib
deb http://security.debian.org/ wheezy/updates main non-free contrib
deb http://archive.debian.org/debian-archive/debian wheezy main contrib
EOF

apt-get update

apt-get install debootstrap

debootstrap --arch $ARCH wheezy /srv/wheezy-$ARCH

cp -p /etc/{hosts,passwd,resolv.conf,group,shadow,gshadow} /srv/wheezy-$ARCH/etc/

cp -p /etc/fstab{,.dist}

mkdir -p /srv/wheezy-$ARCH/lib/modules

cat <<EOF >> /etc/fstab
# for Dell OMSA chroot
/proc /srv/wheezy-$ARCH/proc none rw,rbind 0 0
/sys /srv/wheezy-$ARCH/sys none rw,rbind 0 0
/dev /srv/wheezy-$ARCH/dev none rw,rbind 0 0
/tmp /srv/wheezy-$ARCH/tmp none rw,bind 0 0
/lib/modules /srv/wheezy-$ARCH/lib/modules none rw,bind 0 0
EOF

mount -a

cat <<EOF > /srv/wheezy-$ARCH/etc/apt/sources.list
deb http://mirrors.kernel.org/debian/ wheezy main non-free contrib
deb http://security.debian.org/ wheezy/updates main non-free contrib
EOF

chroot /srv/wheezy-$ARCH apt-get update
chroot /srv/wheezy-$ARCH apt-get -f install
chroot /srv/wheezy-$ARCH apt-get upgrade

echo 'deb http://linux.dell.com/repo/community/ubuntu wheezy openmanage' > /srv/wheezy-$ARCH/etc/apt/sources.list.d/linux.dell.com.sources.list 

# download and trust GPG key for Dell OMSA packages
gpg --keyserver $GPG_KEY_SERVER --recv-key $GPG_KEY_ID
gpg -a --export $GPG_KEY_ID | chroot /srv/wheezy-$ARCH apt-key add -

chroot /srv/wheezy-$ARCH apt-get update
chroot /srv/wheezy-$ARCH apt-get install $OMSA_PACKAGES
## Activate dataeng service at runlevel 2 if you want launched at the next boot (dataeng LSB header has to be fixed, http://lists.us.dell.com/pipermail/linux-poweredge/2011-February/044314.html)
chroot /srv/wheezy-$ARCH update-rc.d dataeng enable 2
chroot /srv/wheezy-$ARCH service dataeng start

echo -n "Testing omreport inside wheezy..."
chroot /srv/wheezy-$ARCH /opt/dell/srvadmin/sbin/omreport chassis info
[ $? -ne 0 ] && echo "fail !!!"

cat <<EOF > /usr/local/bin/wheezy-$ARCH
#!/bin/bash
exec chroot /srv/wheezy-$ARCH "\$0" "\$@"
EOF

chmod 755 /usr/local/bin/wheezy-$ARCH
ln -s /usr/local/bin/wheezy-$ARCH /etc/init.d/dataeng
ln -s /usr/local/bin/wheezy-$ARCH /etc/init.d/instsvcdrv
ln -s /usr/local/bin/wheezy-$ARCH /etc/init.d/dsm_om_connsvc

# Adjust lenny LSB scripts to chrooted Dell OMSA init.d scripts, they have to be in the same path to be launched at boot
chroot /srv/wheezy-$ARCH/ find /etc/rc?.d/ -name "*dataeng" | xargs -ipath ln -s /etc/init.d/dataeng path
chroot /srv/wheezy-$ARCH/ find /etc/rc?.d/ -name "*fancontrol" | xargs -ipath ln -s /etc/init.d/fancontrol path

mkdir -p /opt/dell/srvadmin/bin
ln -s /usr/local/bin/wheezy-$ARCH /opt/dell/srvadmin/bin/omreport
ln -s /usr/local/bin/wheezy-$ARCH /opt/dell/srvadmin/bin/omconfig
ln -s /usr/local/bin/wheezy-$ARCH /opt/dell/srvadmin/bin/omshell

## Remove wheezy repository from your Debian Lenny installation which may cause your system broken if you make some upgrade via apt*.
rm /etc/apt/sources.list.d/debian.wheezy.sources.list
apt-get update

# This could display to you some basic information about your hardware
echo -n "Testing omreport inside lenny..."
/opt/dell/srvadmin/bin/omreport chassis info
[ $? -ne 0 ] && echo "fail"
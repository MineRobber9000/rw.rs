#!/bin/bash
set -eux
source "$(cd $(dirname "${BASH_SOURCE[0]}") &>/dev/null && pwd)/common.sh"

# install packages
apt install -y build-essential libtool libtool-bin sudo quota net-tools curl \
    git zsh vim emacs nano mle screen tmux irssi weechat inspircd subversion \
    libxml2-dev libpcre3-dev strace gdb socat sqlite3

# configure quota
if [ ! -f /aquota.user ]; then
    awk -vq=$quota_path \
        '{if($2==q){ $4=$4",usrjquota=aquota.user,jqfmt=vfsv1" } print}' \
        /etc/fstab >/etc/fstab.new
    mv -vf /etc/fstab.new /etc/fstab
    mount -vo remount $quota_path
    quotacheck -ucm $quota_path
    quotaon -v $quota_path
fi

# configure sshd
if ! diff "$rwrs_root/etc/sshd_config" /etc/ssh/sshd_config &>/dev/null; then
    cp -vf "$rwrs_root/etc/sshd_config" /etc/ssh/
    systemctl restart sshd
fi

# configure restricted user slice
if ! diff "$rwrs_root/etc/user-restricted.slice.conf" \
          "$restricted_slice_dir/user-restricted.slice.conf" &>/dev/null; then
    mkdir -p $restricted_slice_dir
    cp -vf "$rwrs_root/etc/user-restricted.slice.conf" $restricted_slice_dir
    systemctl daemon-reload
fi

# configure cron
if ! diff "$rwrs_root/etc/cron" /etc/cron.d/rw-rs &>/dev/null; then
    cp -vf "$rwrs_root/etc/cron" /etc/cron.d/rw-rs
fi

# configure ircd
if ! diff "$rwrs_root/etc/inspircd.conf" \
          /etc/inspircd/inspircd.conf &>/dev/null; then
    cp -vf "$rwrs_root/etc/inspircd.conf" /etc/inspircd/inspircd.conf
    ircd_pass=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 24)
    sed -i "s/@ircdpasshere@/$ircd_pass/g" /etc/inspircd/inspircd.conf
    touch /etc/inspircd/inspircd.motd
    chown -R irc:irc /etc/inspircd/
    chmod 700 /etc/inspircd/
    chmod 600 /etc/inspircd/inspircd.conf
    systemctl restart inspircd
fi

# build apache
if [ ! -f /usr/httpd/bin/httpd ]; then
    pushd ~
    wget "https://github.com/apache/httpd/archive/${httpd_version}.tar.gz"
    tar xf "${httpd_version}.tar.gz"
    pushd "httpd-${httpd_version}"
    svn co http://svn.apache.org/repos/asf/apr/apr/trunk srclib/apr
    ./buildconf
    ./configure --prefix=/usr/httpd --with-included-apr --with-libxml2=/usr \
        --enable-mods-shared=all --enable-mpms-shared=all --enable-suexec \
        --enable-proxy --enable-cgi --enable-userdir
    make
    make install
    popd
    groupadd apache
    useradd -r -d /usr/httpd -s /usr/sbin/nologin -g apache apache
    popd
fi

# configure apache
httpd_diff=0
diff "$rwrs_root/etc/httpd.service" /etc/systemd/system/httpd.service
httpd_diff=$((httpd_diff+$?))
diff "$rwrs_root/etc/httpd.conf" /usr/httpd/conf/httpd.conf
httpd_diff=$((httpd_diff+$?))
if [ "$httpd_diff" -ne 0 ]; then
    cp -vf "$rwrs_root/etc/httpd.service" /etc/systemd/system/
    cp -vf "$rwrs_root/etc/httpd.conf" /usr/httpd/conf/
    rm -rf /usr/httpd/htdocs
    ln -s "$rwrs_root/htdocs" /usr/httpd/htdocs
    systemctl daemon-reload
    systemctl enable httpd
    systemctl start httpd
fi

# TODO tls ircd
# TODO simple alerting
# TODO smoker tests

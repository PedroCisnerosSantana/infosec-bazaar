#!/bin/bash

# Honeypot AutoInstall Script v0.3
# by Chris Campbell
#
# Twitter: @phage_nz
# GitHub: phage-nz
# Blog: https://phage.nz

# Installs:
# Dionaea
# p0f
# Cowrie
#
# Tested on Ubuntu 14.04 (EC2 t2.micro instance)

# Variables:
INSTALL_DIONAEA="yes" # yes or no.
INSTALL_COWRIE="no" # yes or no.

SSL_C="US" # Country code.
SSL_CN="example.company.com" # Certificate CN.
SSL_O="Example Company Ltd."  # Company name.
SSL_OU="OU" # Organisational unit.

DOMAIN="WORKGROUP" # Domain name.
SERVER="EXAMPLE-SERVER" # Server name.

VT_KEY="" # Your VirusTotal API key.

#
# SCRIPT START
#

# Install must be done as root.
if [ "$EUID" -ne 0 ]
  then echo "Please run as root!"
  exit 1
fi

# Install dependencies if either Dionaea or Cowrie is to be installed.
if [ "$INSTALL_DIONAEA" == "yes" ] || [ "$INSTALL_COWRIE" == "yes" ] ; then
  echo "Updating server..."
  apt update
  apt upgrade -y
  echo "Installing dependencies..."
  apt install autoconf automake build-essential check cython3 git libcurl4-openssl-dev libemu-dev libev-dev libffi-dev libglib2.0-dev libgmp-dev libloudmouth1-dev libmpc-dev libmpfr-dev libnetfilter-queue-dev libnl-dev libpcap-dev libpython-dev libreadline-dev libsqlite3-dev libssl-dev libtool libudns-dev libxml2-dev libxslt1-dev p0f python-dev python-pip python-software-properties python-virtualenv python3 python3-dev python3-yaml software-properties-common -y
  # Cowrie requires the latest version of Python OpenSSL.
  apt remove python-openssl
  pip install pyopenssl
else
  echo "Nothing to be installed."
  exit 0
fi

# Install Dionaea.
if [ "$INSTALL_DIONAEA" == "yes" ]; then
  echo "Installing Dionaea..."
  cd /opt
  git clone -b WannaCry https://github.com/DinoTools/dionaea.git
  cd dionaea
  git clone https://github.com/gento/liblcfg
  cd liblcfg/code
  autoreconf -vi
  ./configure --prefix=/opt/dionaea
  make install
  cd ../..
  autoreconf -vi
  ./configure \
    --disable-werror \
    --prefix=/opt/dionaea \
    --with-python=/usr/bin/python3 \
    --with-cython-dir=/usr/bin \
    --with-ev-include=/usr/include \
    --with-ev-lib=/usr/lib \
    --with-emu-lib=/usr/lib/libemu \
    --with-emu-include=/usr/include \
    --with-gc-include=/usr/include/gc \
    --enable-nl \
    --with-nl-include=/usr/include/libnl3 \
    --with-nl-lib=/usr/lib \
    --with-lcfg-lib=/opt/dionaea/lib/ \
    --with-curl-config=/usr/bin/
  make
  make install
  echo "Making underprivileged user..."
  useradd -r -s /bin/false dionaea
  chown -R dionaea:dionaea /opt/dionaea/
  mkdir /home/dionaea
  chown dionaea:dionaea /home/dionaea
  echo "Making Dionaea honeypot database..."
  mkdir /opt/dionaea/var/dionaea/scripts
  wget https://raw.githubusercontent.com/phage-nz/malware-hunting/master/honeypot/generate_user_db.py -P /opt/dionaea/var/dionaea/scripts
  wget https://raw.githubusercontent.com/phage-nz/malware-hunting/master/honeypot/wordlist.txt -P /opt/dionaea/var/dionaea/scripts
  chown -R dionaea:dionaea /opt/dionaea/var/dionaea/scripts
  chmod +x /opt/dionaea/var/dionaea/scripts/generate_user_db.py
  sudo -u dionaea touch /opt/dionaea/var/dionaea/target_db.sqlite
  sudo -u dionaea /opt/dionaea/var/dionaea/scripts/generate_user_db.py
  echo "Fixing up Dionaea config files..."
  sed -e '/errors.filename/ s/^#*/#/' -i /opt/dionaea/etc/dionaea/dionaea.cfg
  sed -e '/errors.levels/ s/^#*/#/' -i /opt/dionaea/etc/dionaea/dionaea.cfg
  sed -e '/errors.domains/ s/^#*/#/' -i /opt/dionaea/etc/dionaea/dionaea.cfg
  sed -i 's/^\(default.levels=\).*/\1all,-debug/' /opt/dionaea/etc/dionaea/dionaea.cfg
  sed -i 's/# ssl.default/ssl.default/g' /opt/dionaea/etc/dionaea/dionaea.cfg
  sed -i 's/^\(ssl.default.c=\).*/\1'"$SSL_C"'/' /opt/dionaea/etc/dionaea/dionaea.cfg
  sed -i 's/^\(ssl.default.cn=\).*/\1'"$SSL_CN"'/' /opt/dionaea/etc/dionaea/dionaea.cfg
  sed -i 's/^\(ssl.default.o=\).*/\1'"$SSL_O"'/' /opt/dionaea/etc/dionaea/dionaea.cfg
  sed -i 's/^\(ssl.default.ou=\).*/\1'"$SSL_OU"'/' /opt/dionaea/etc/dionaea/dionaea.cfg
  sed -i '9,10 s/^#//' /opt/dionaea/etc/dionaea/services-available/mysql.yaml
  sed -i 's/\/path\/to\/cc_info.sqlite/\/opt\/dionaea\/var\/dionaea\/target_db.sqlite/g' /opt/dionaea/etc/dionaea/services-available/mysql.yaml
  sed -i 's/apikey: "........."/apikey: "'"$VT_KEY"'"/g' /opt/dionaea/etc/dionaea/ihandlers-available/virustotal.yaml
  sed -i '4,6 s/^#//' /opt/dionaea/etc/dionaea/services-available/pptp.yaml
  sed -e '/self.make_comment/ s/^#*/#/' -i /opt/dionaea/lib/dionaea/python/dionaea/virustotal.py
  sed -e '/self.root_path\s*=\s*/ s/^#*/#/' -i /opt/dionaea/lib/dionaea/python/dionaea/sip/extras.py
  sed -e '/self.users\s*=\s*/ s/^#*/#/' -i /opt/dionaea/lib/dionaea/python/dionaea/sip/extras.py
  sed -i 's/sqlite3.connect(self.users)/sqlite3.connect("\/opt\/dionaea\/var\/dionaea\/sipaccounts.sqlite")/g' /opt/dionaea/lib/dionaea/python/dionaea/sip/extras.py
  sed -i 's/"OemDomainName", "WORKGROUP"/"OemDomainName", "'"$DOMAIN"'"/g' /opt/dionaea/lib/dionaea/python/dionaea/smb/include/smbfields.py
  sed -i 's/"ServerName", "HOMEUSER-3AF6FE"/"ServerName", "'"$SERVER"'"/g' /opt/dionaea/lib/dionaea/python/dionaea/smb/include/smbfields.py
  sed -i  's/^\(\s*r\.VersionToken\.TokenType\s*=\s*\).*$/\10xAA/' /opt/dionaea/lib/dionaea/python/dionaea/mssql/mssql.py
  echo "Enabling VirusTotal handler..."
  sudo -u dionaea ln -s /opt/dionaea/etc/dionaea/ihandlers-available/virustotal.yaml /opt/dionaea/etc/dionaea/ihandlers-enabled 
  echo "Enabling Dionaea p0f handler..."
  sudo -u dionaea ln -s /opt/dionaea/etc/dionaea/ihandlers-available/p0f.yaml /opt/dionaea/etc/dionaea/ihandlers-enabled
  echo "Making a folder for SIP pcap's..."
  sudo -u dionaea mkdir -p /opt/dionaea/var/dionaea/rtp/default
  echo "Making logrotate script..."
  wget https://raw.githubusercontent.com/phage-nz/malware-hunting/master/honeypot/dionaea.logrotate -O /etc/logrotate.d/dionaea
  echo "Setting all services to autostart..."
  wget https://raw.githubusercontent.com/phage-nz/malware-hunting/master/honeypot/dionaea.init -O /etc/init.d/dionaea
  wget https://raw.githubusercontent.com/phage-nz/malware-hunting/master/honeypot/p0f.init -O /etc/init.d/p0f
  chmod +x /etc/init.d/dionaea
  chmod +x /etc/init.d/p0f
  update-rc.d dionaea defaults
  update-rc.d p0f defaults
  echo "Starting services..."
  /etc/init.d/p0f start
  /etc/init.d/dionaea start
  echo "Dionaea install complete! You may wish to alter the enabled handlers and services in /opt/dionaea/etc/dionaea."
fi

# Install Cowrie.
if [ "$INSTALL_COWRIE" == "yes" ]; then
  echo "Installing Cowrie..."
  cd /opt
  git clone https://github.com/micheloosterhof/cowrie
  cp /opt/cowrie/cowrie.cfg.dist /opt/cowrie/cowrie.cfg
  echo "Installing Python dependencies..."
  pip install -r requirements.txt
  echo "Making underprivileged user..."
  useradd -r -s /bin/false cowrie
  mkdir -p /var/run/cowrie
  chown -R cowrie:cowrie /opt/cowrie/
  chown -R cowrie:cowrie /var/run/cowrie/
  mkdir /home/cowrie
  chown cowrie:cowrie /home/cowrie
  echo "Fixing up the Cowrie config file..."
  sed -i 's/^\(hostname\s*=\s*\).*/\1'"$SERVER"'/' /opt/cowrie/cowrie.cfg
  echo "Making the Cowrie filesystem..."
  /opt/cowrie/bin/createfs
  echo "Making logrotate script..."
  wget https://raw.githubusercontent.com/phage-nz/malware-hunting/master/honeypot/cowrie.logrotate -O /etc/logrotate.d/cowrie
  echo "Setting service to autostart..."
  wget https://raw.githubusercontent.com/phage-nz/malware-hunting/master/honeypot/cowrie.init -O /etc/init.d/cowrie
  chmod +x /etc/init.d/cowrie
  update-rc.d cowrie defaults
  echo "Redirecting port 22 to Cowrie. You will need to re-establish your SSH session on port 8925 after the service reloads."
  sed -i 's/Port 22/Port 8925/g' /etc/ssh/sshd_config
  service ssh reload
  iptables -t nat -A PREROUTING -p tcp --dport 22 -j REDIRECT --to-port 2222
  iptables-save > /etc/iptables.rules
  echo '#!/bin/sh' >> /etc/network/if-up.d/iptablesload 
  echo 'iptables-restore < /etc/iptables.rules' >> /etc/network/if-up.d/iptablesload 
  echo 'exit 0' >> /etc/network/if-up.d/iptablesload
  chmod +x /etc/network/if-up.d/iptablesload
  echo "Starting service..."
  /etc/init.d/cowrie start
  echo "Cowrie install complete!"
fi

exit 0

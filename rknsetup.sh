#!/bin/bash

exiterr()  { echo "Error: $1" >&2; exit 1; }

apt-get -yq install software-properties-common git || exiterr "rknsetup - software-properties-common or git install failed."
add-apt-repository -y ppa:cz.nic-labs/bird
apt-get -yq update || exiterr "rknsetup - 'apt-get update' failed."
apt-get -yq --allow-unauthenticated install bird || exiterr "rknsetup - bird install failed."

systemctl stop bird6
systemctl disable bird6
systemctl stop bird

cat > /etc/bird/bird.conf <<'EOF'
log syslog all;
router id 192.168.42.1;

protocol kernel {
        scan time 60;
        import none;
        export none;
}

protocol device {
        scan time 60;
}

protocol static static_bgp {
    include "ipsum.txt";
}

protocol bgp OurRouter {
        description "Our Router";
        neighbor 192.168.42.10 as 64999;
        import none;
        export where proto = "static_bgp";
        next hop self;
        local as 64999;
        source address 192.168.42.1;
        passive off;
}
EOF

rm -rf /root/blacklist/minimizer/
git clone -b stable https://github.com/phoenix-mstu/net_list_minimizer.git /root/blacklist/minimizer/

mkdir -p /root/blacklist/list
mkdir -p /root/blacklist/minimized_list
cd /root/blacklist

echo "1" > /root/blacklist/md5.txt
cat > /root/blacklist/chklist <<'EOF'
#!/bin/bash
cd /root/blacklist/list
wget -N https://antifilter.download/list/ip.lst https://antifilter.download/list/subnet.lst
old=$(cat /root/blacklist/md5.txt);
new=$(cat /root/blacklist/list/*.lst | md5sum | head -c 32);
echo $old $new
if [ "$old" != "$new" ]
then
	cat /root/blacklist/list/* > /root/blacklist/minimized_list/joined.txt
	python3 /root/blacklist/minimizer/minimize_net_list.py /root/blacklist/minimized_list/joined.txt 30000 | grep -v '###' > /root/blacklist/minimized_list/result.txt	
	cat /root/blacklist/minimized_list/result.txt | sed 's_.*_route & reject;_' > /etc/bird/ipsum.txt	
	#cat /root/blacklist/list/ipsum.lst | sed 's_.*_route & reject;_' > /etc/bird/ipsum.txt
	#cat /root/blacklist/list/subnet.lst | sed 's_.*_route & reject;_' > /etc/bird/subnet.txt
	/usr/sbin/birdc configure;
	logger "RKN list reconfigured";
	echo $new > /root/blacklist/md5.txt;
fi
EOF

chmod +x /root/blacklist/chklist
systemctl start bird
/root/blacklist/chklist

crontab -l | { cat; echo "*/30 * * * * bash /root/blacklist/chklist"; } | crontab -

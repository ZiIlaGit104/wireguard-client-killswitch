# wireguard-client-killswitch
Adds iptables rules to disable IPv6 and killswitch for any internet traffic not bound for the VPN tunnel.  Also allows local/private traffic, while limiting DNS traffic as an extra layer of leak protection.

Recommended to call it by including in your wg0.conf file’s '[Interface]' Section as a 'PostUp' command like:

```
[Interface]
PrivateKey = 123213123123123123123123123123123=
Address = 101.101.101.3/32
DNS = 199.99.0.1, 199.99.0.2

#Add killswitch iptables rules
PostUp = /config/killswitch.sh

[Peer]
PublicKey = 123123123123123123123123123123123123=
AllowedIPs = 0.0.0.0/0
Endpoint = 222.333.44.55:51820
```

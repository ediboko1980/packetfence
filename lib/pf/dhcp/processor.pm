package pf::dhcp::processor;

=head1 NAME

pf::dhcp::processor

=cut

=head1 DESCRIPTION

Processes DHCP packets

=cut

use strict;
use warnings;

use Try::Tiny;
use pf::client;
use pf::constants;
use pf::constants::dhcp qw($DEFAULT_LEASE_LENGTH);
use pf::clustermgmt;
use pf::config;
use pf::config::cached;
use pf::db;
use pf::firewallsso;
use pf::inline::custom $INLINE_API_LEVEL;
use pf::iplog;
use pf::lookup::node;
use pf::node;
use pf::util;
use pf::config::util;
use pf::services::util;
use pf::util::dhcp;
use List::MoreUtils qw(any);
use pf::api::jsonrpcclient;
use NetAddr::IP;
use pf::SwitchFactory;
use pf::log(service => 'pfdhcplistener');

our $logger = get_logger;
my $force_update_on_ack = isenabled($Config{network}{force_listener_update_on_ack});
my %rogue_servers;
my $ROGUE_DHCP_TRIGGER = '1100010';
my @local_dhcp_servers_mac;
my @local_dhcp_servers_ip;

=head2 new

Create a new DHCP processor

=cut

sub new {
    my ( $class, %argv ) = @_;
    my $self = bless {}, $class;
    foreach my $attr (keys %argv){
        $self->{$attr} = $argv{$attr};
    }
    if($self->{is_inline_vlan}){
        $self->{accessControl} = new pf::inline::custom();
    }
    $self->{api_client} = pf::client::getClient();
    return $self;
}

=head2 process_packet

Process a packet

=cut

sub process_packet {
    my ( $self ) = @_;

    my ($dhcp);

    # we need success flag here because we can't next inside try catch
    my $success;
    try {
        $dhcp = decode_dhcp($self->{'udp_payload'});
        $success = 1;
    } catch {
        $logger->warn("Unable to parse DHCP packet: $_");
    };
    return if (!$success);

    # adding to dhcp hashref some frame information we care about
    $dhcp->{'src_mac'} = $self->{'src_mac'};
    $dhcp->{'dest_mac'} = $self->{'dest_mac'};
    $dhcp->{'src_ip'} = $self->{'src_ip'};
    $dhcp->{'dest_ip'} = $self->{'dest_ip'};

    if (!valid_mac($dhcp->{'src_mac'})) {
        $logger->debug("Source MAC is invalid. skipping");
        return;
    }

    # grab DHCP information
    if ( !defined($dhcp->{'chaddr'}) ) {
        $logger->debug("chaddr is undefined in DHCP packet");
        return;
    }

    $dhcp->{'chaddr'} = clean_mac( substr( $dhcp->{'chaddr'}, 0, 12 ) );
    if ( $dhcp->{'chaddr'} ne "00:00:00:00:00:00" && !valid_mac($dhcp->{'chaddr'}) ) {
        $logger->debug(
            "invalid CHADDR value ($dhcp->{'chaddr'}) in DHCP packet from $dhcp->{src_mac} ($dhcp->{src_ip})"
        );
        return;
    }

    if ( !node_exist($dhcp->{'chaddr'}) ) {
        $logger->info("Unseen before node added: $dhcp->{'chaddr'}");
        node_add_simple($dhcp->{'chaddr'});
    }

    # opcode 1 = request, opcode 2 = reply

    # Option 53: DHCP Message Type (RFC2132)
    # Value   Message Type
    # -----   ------------
    #   1     DHCPDISCOVER
    #   2     DHCPOFFER
    #   3     DHCPREQUEST
    #   4     DHCPDECLINE
    #   5     DHCPACK
    #   6     DHCPNAK
    #   7     DHCPRELEASE
    #   8     DHCPINFORM

    if ( $dhcp->{'op'} == 2 ) {
        $self->parse_dhcp_offer($dhcp) if ( $dhcp->{'options'}{'53'} == 2 );

        $self->parse_dhcp_ack($dhcp) if ( $dhcp->{'options'}{'53'} == 5 );

    } elsif ( $dhcp->{'op'} == 1 ) {

        # returning on Discover in order to avoid some unnecessary work (we expect clients to do a dhcp request anyway)
        return $self->parse_dhcp_discover($dhcp) if ( $dhcp->{'options'}{'53'} == 1 );

        $self->parse_dhcp_request($dhcp) if ( $dhcp->{'options'}{'53'} == 3 );

        return $self->parse_dhcp_release($dhcp) if ( $dhcp->{'options'}{'53'} == 7 );

        return $self->parse_dhcp_inform($dhcp) if ( $dhcp->{'options'}{'53'} == 8 );

        # Option 82 Relay Agent Information (RFC3046)
        if ( isenabled( $Config{'network'}{'dhcpoption82logger'} ) && defined( $dhcp->{'options'}{'82'} ) ) {
            $self->parse_dhcp_option82($dhcp);
        }

        # updating the node first
        # in case the fingerprint generates a violation and that autoreg uses fingerprint to auto-categorize nodes
        # see #1216 for details
        my %tmp;
        $tmp{'dhcp_fingerprint'} = defined($dhcp->{'options'}{'55'}) ? $dhcp->{'options'}{'55'} : '';
        $tmp{'dhcp_vendor'} = defined($dhcp->{'options'}{'60'}) ? $dhcp->{'options'}{'60'} : '';
        $tmp{'last_dhcp'} = mysql_date();
        if (defined($dhcp->{'options'}{'12'})) {
            $tmp{'computername'} = $dhcp->{'options'}{'12'};
            if(isenabled($Config{network}{hostname_change_detection})){
                $self->{api_client}->notify('detect_computername_change', $dhcp->{'chaddr'}, $tmp{'computername'});
            }
        }

        node_modify( $dhcp->{'chaddr'}, %tmp );

        # Fingerbank interaction
        my %fingerbank_query_args = (
            dhcp_fingerprint    => $tmp{'dhcp_fingerprint'},
            dhcp_vendor         => $tmp{'dhcp_vendor'},
            mac                 => $dhcp->{'chaddr'},
            # When listening on the mgmt interface, we can't rely on yiaddr as we only see requests
            ip                  => ($dhcp->{'yiaddr'} ne "0.0.0.0") ? $dhcp->{'yiaddr'} : $dhcp->{'options'}{'50'},
        );
        $self->{api_client}->notify('fingerbank_process', \%fingerbank_query_args );

        my $modified_node_log_message = '';
        foreach my $node_key ( keys %tmp ) {
            $modified_node_log_message .= "$node_key = " . $tmp{$node_key} . ",";
        }
        chop($modified_node_log_message);

        $logger->info("$dhcp->{'chaddr'} requested an IP with the following informations: $modified_node_log_message");
    } else {
        $logger->debug("unrecognized DHCP opcode from $dhcp->{'chaddr'}: $dhcp->{op}");
    }
}

=head2 parse_dhcp_discover

=cut

sub parse_dhcp_discover {
    my ($self, $dhcp) = @_;
    $logger->debug("DHCPDISCOVER from $dhcp->{'chaddr'}");
}

=head2 parse_dhcp_offer

=cut

sub parse_dhcp_offer {
    my ($self, $dhcp) = @_;

    if ($dhcp->{'yiaddr'} =~ /^0\.0\.0\.0$/) {
        $logger->warn("DHCPOFFER invalid IP in DHCP's yiaddr for $dhcp->{'chaddr'}");
        return;
    }

    $logger->info("DHCPOFFER from $dhcp->{src_ip} ($dhcp->{src_mac}) to host $dhcp->{'chaddr'} ($dhcp->{yiaddr})");

    $self->rogue_dhcp_handling($dhcp->{'src_ip'}, $dhcp->{'src_mac'}, $dhcp->{'yiaddr'}, $dhcp->{'chaddr'}, $dhcp->{'giaddr'});
}

=head2 parse_dhcp_request

=cut

sub parse_dhcp_request {
    my ($self, $dhcp) = @_;
    $logger->debug("DHCPREQUEST from $dhcp->{'chaddr'}");

    my $lease_length = $dhcp->{'options'}{'51'};
    my $client_ip = $dhcp->{'options'}{'50'};
    my $client_mac;
    if (defined($client_ip) && $client_ip !~ /^0\.0\.0\.0$/) {
        $logger->info(
            "DHCPREQUEST from $dhcp->{'chaddr'} ($client_ip)"
            . ( defined($lease_length) ? " with lease of $lease_length seconds" : "")
        );
        $client_mac = $dhcp->{'chaddr'};
    }

    # We check if we are running without dhcpd
    # This means we don't see ACK so we need to act on requests
    if((!$self->{running_w_dhcpd} && !$force_update_on_ack) && (defined($client_ip) && defined($client_mac))){
        $self->handle_new_ip($client_mac, $client_ip, $lease_length);
    }

    # As per RFC2131 in a DHCPREQUEST if ciaddr is set and we broadcast, we are in re-binding state
    # in which case we are not interested in detecting rogue DHCP
    if ($dhcp->{'ciaddr'} !~ /^0\.0\.0\.0$/) {
        $self->rogue_dhcp_handling($dhcp->{'options'}{54}, undef, $client_ip, $dhcp->{'chaddr'}, $dhcp->{'giaddr'});
    }

    if ($self->{is_inline_vlan} || grep ( { $_->{'gateway'} eq $dhcp->{'src_ip'} } @inline_nets)) {
        $self->{api_client}->notify('synchronize_locationlog',$self->{interface_ip},$self->{interface_ip},undef, $NO_PORT, $self->{interface_vlan}, $dhcp->{'chaddr'}, $NO_VOIP, $INLINE);
        $self->{accessControl}->performInlineEnforcement($dhcp->{'chaddr'});
    }
}


=head2 parse_dhcp_ack

=cut

sub parse_dhcp_ack {
    my ($self, $dhcp) = @_;

    my $s_ip = $dhcp->{'src_ip'};
    my $s_mac = $dhcp->{'src_mac'};
    my $lease_length = $dhcp->{'options'}->{'51'};

    my $client_ip;
    my $client_mac;

    if ($dhcp->{'yiaddr'} !~ /^0\.0\.0\.0$/) {
        $logger->info(
            "DHCPACK from $s_ip ($s_mac) to host $dhcp->{'chaddr'} ($dhcp->{yiaddr})"
            . ( defined($lease_length) ? " for $lease_length seconds" : "" )
        );
        $client_ip = $dhcp->{'yiaddr'};
        $client_mac = $dhcp->{'chaddr'};
    } 
    elsif ($dhcp->{'ciaddr'} !~ /^0\.0\.0\.0$/) {

        $logger->info(
            "DHCPACK CIADDR from $s_ip ($s_mac) to host $dhcp->{'chaddr'} ($dhcp->{ciaddr})"
            . ( defined($lease_length) ? " for $lease_length seconds" : "")
        );
        $client_ip = $dhcp->{'ciaddr'};
        $client_mac = $dhcp->{'chaddr'};
    } 
    else {
        $logger->warn(
            "invalid DHCPACK from $s_ip ($s_mac) to host $dhcp->{'chaddr'} [$dhcp->{yiaddr} - $dhcp->{ciaddr}]"
        );
    }

    # We check if we are running with the DHCPd process.
    # If yes, we are interested with the ACK
    # Packet also has to be valid
    if(($self->{running_w_dhcpd} || $force_update_on_ack) && (defined($client_ip) && defined($client_mac))){
        $self->handle_new_ip($client_mac, $client_ip, $lease_length);
    }
    else {
        $logger->debug("Not acting on DHCPACK");
    }

}

=head2 handle_new_ip

Handle the tasks related to a device getting an IP address

=cut

sub handle_new_ip {
    my ($self, $client_mac, $client_ip, $lease_length) = @_;
    $logger->info("Updating iplog and SSO for $client_mac -> $client_ip");
    $self->update_iplog( $client_mac, $client_ip, $lease_length );

    my %data = (
       'ip' => $client_ip,
       'mac' => $client_mac,
       'net_type' => $self->{net_type},
    );
    $self->{api_client}->notify('trigger_scan', %data );
    my $firewallsso = pf::firewallsso->new;
    $firewallsso->do_sso('Update', $client_mac, $client_ip, $lease_length || $DEFAULT_LEASE_LENGTH);
}

=head2 parse_dhcp_release

=cut

sub parse_dhcp_release {
    my ($self, $dhcp) = @_;
    $logger->debug("DHCPRELEASE from $dhcp->{'chaddr'} ($dhcp->{ciaddr})");
    $self->{api_client}->notify('close_iplog',$dhcp->{'ciaddr'});
}

=head2 parse_dhcp_inform

=cut

sub parse_dhcp_inform {
    my ($self, $dhcp) = @_;
    $logger->debug("DHCPINFORM from $dhcp->{'chaddr'} ($dhcp->{ciaddr})");
}

=head2 rogue_dhcp_handling

Requires DHCP Server IP

Optional but very useful DHCP Server MAC

=cut

sub rogue_dhcp_handling {
    my ($self, $dhcp_srv_ip, $dhcp_srv_mac, $offered_ip, $client_mac, $relay_ip) = @_;

    return if (isdisabled($Config{'network'}{'rogue_dhcp_detection'}));

    # if server ip is empty, it means that the client is asking for it's old IP and this should be legit
    if (!defined($dhcp_srv_ip)) {
        $logger->debug(
            "received empty DHCP Server IP in rogue detection. " .
            "Offered IP: " . ( defined($offered_ip) ? $offered_ip : 'unknown' )
        );
        return;
    }

    # ignore local DHCP servers
    return if ( grep({$_ eq $dhcp_srv_ip} get_local_dhcp_servers_by_ip()) );
    if ( defined($dhcp_srv_mac) ) {
        return if ( grep({$_ eq $dhcp_srv_mac} get_local_dhcp_servers_by_mac()) );
    }

    # ignore whitelisted DHCP servers
    return if ( grep({$_ eq $dhcp_srv_ip} split(/\s*,\s*/, $Config{'general'}{'dhcpservers'})) );

    my $rogue_offer = sprintf( "%s: %15s to %s on interface %s", mysql_date(), $offered_ip, $client_mac, $self->{interface} );
    if (defined($relay_ip) && $relay_ip !~ /^0\.0\.0\.0$/) {
        $rogue_offer .= " received via relay $relay_ip";
    }
    $rogue_offer .= "\n";
    push @{ $rogue_servers{$dhcp_srv_ip} }, $rogue_offer;

    # if I have a MAC use it, otherwise look it up
    $dhcp_srv_mac = pf::iplog::ip2mac($dhcp_srv_ip) if (!defined($dhcp_srv_mac));
    if ($dhcp_srv_mac) {
        my %data = (
           'mac' => $dhcp_srv_mac,
           'tid' => $ROGUE_DHCP_TRIGGER,
           'type' => 'INTERNAL',
        );
        $self->{api_client}->notify('trigger_violation', %data );
    } else {
        $logger->info("Unable to find MAC based on IP $dhcp_srv_ip for rogue DHCP server");
        $dhcp_srv_mac = 'unknown';
    }

    $logger->warn("$dhcp_srv_ip ($dhcp_srv_mac) was detected offering $offered_ip to $client_mac on ".$self->{interface});
    if (scalar( @{ $rogue_servers{$dhcp_srv_ip} } ) == $Config{'network'}{'rogueinterval'} ) {
        my %rogue_message;
        $rogue_message{'subject'} = "ROGUE DHCP SERVER DETECTED AT $dhcp_srv_ip ($dhcp_srv_mac) ON ".$self->{interface}."\n";
        $rogue_message{'message'} = '';
        if ($dhcp_srv_mac ne 'unknown') {
            $rogue_message{'message'} .= pf::lookup::node::lookup_node($dhcp_srv_mac) . "\n";
        }
        $rogue_message{'message'} .= "Detected Offers\n---------------\n";
        while ( @{ $rogue_servers{$dhcp_srv_ip} } ) {
            $rogue_message{'message'} .= pop( @{ $rogue_servers{$dhcp_srv_ip} } );
        }
        $rogue_message{'message'} .=
            "\n\nIf this DHCP Server is legitimate, make sure to add it to the dhcpservers list under General.\n"
        ;
        pfmailer(%rogue_message);
    }
}


=head2 parse_dhcp_option82

Option 82 is Relay Agent Information. Defined in RFC 3046.

=cut

sub parse_dhcp_option82 {
    my ($self, $dhcp) = @_;

    # slicing the hash to retrive the stuff we are interested in
    my ($switch, $vlan, $mod, $port)  = @{$dhcp->{'options'}{'82'}}{'switch', 'vlan', 'module', 'port'};
    if ( defined($switch) && defined($vlan) && defined($mod) && defined($port) ) {

        # TODO port should be translated into ifIndex
        # FIXME option82 stuff needs to be re-validated (#1340)
        $self->{api_client}->notify('insert_close_locationlog',$switch, $mod . '/' . $port, $vlan, $dhcp->{'chaddr'}, '');
    }
}

=head2 update_iplog

Update the iplog entry for a device
Also handles the SSO stop if the IP changes

=cut

sub update_iplog {
    my ( $self, $srcmac, $srcip, $lease_length ) = @_;
    $logger->debug("$srcip && $srcmac");

    # return if MAC or IP is not valid
    if ( !valid_mac($srcmac) || !valid_ip($srcip) ) {
        $logger->error("invalid MAC or IP: $srcmac $srcip");
        return;
    }

    my $oldip  = pf::iplog::mac2ip($srcmac);
    my $oldmac = pf::iplog::ip2mac($srcip);
    if ( $oldip && $oldip ne $srcip ) {
        my $view_mac = node_view($srcmac);
        my $firewallsso = pf::firewallsso->new;
        $firewallsso->do_sso('Stop',$oldmac,$oldip,undef);
        $firewallsso->do_sso('Start', $srcmac, $srcip, $lease_length || $DEFAULT_LEASE_LENGTH);

        if ($view_mac->{'last_connection_type'} eq $connection_type_to_str{$INLINE}) {
            $self->{api_client}->notify('ipset_node_update',$oldip, $srcip, $srcmac);
        }
    }
    my %data = (
        'mac' => $srcmac,
        'ip' => $srcip,
        'lease_length' => $lease_length,
        'oldip' => $oldip,
        'oldmac' => $oldmac,
    );
    $self->{api_client}->notify('update_iplog', %data);
}

=head2 get_local_dhcp_servers_by_ip

Return a list of all dhcp servers IP that could be running locally.

Caches results on first run then returns from cache.

TODO: Should be refactored and putted into a class. IP and MAC methods should also be put into a single one.

=cut

sub get_local_dhcp_servers_by_ip {

    # return from cache
    return @local_dhcp_servers_ip if (@local_dhcp_servers_ip);

    # look them up, fill cache and return result
    foreach my $network (keys %ConfigNetworks) {

        push @local_dhcp_servers_ip, $ConfigNetworks{$network}{'gateway'}
            if ($ConfigNetworks{$network}{'dhcpd'} eq 'enabled');
    }
    return @local_dhcp_servers_ip;
}

=head2 get_local_dhcp_servers_by_mac

Return a list of all mac addresses that could be issuing DHCP offers/acks locally.

Caches results on first run then returns from cache.

TODO: Should be refactored and putted into a class. IP and MAC methods should also be put into a single one.

=cut

sub get_local_dhcp_servers_by_mac {
    # return from cache
    return @local_dhcp_servers_mac if ( @local_dhcp_servers_mac );

    # look them up, fill cache and return result
    @local_dhcp_servers_mac = get_internal_macs();

    return @local_dhcp_servers_mac;
}

=head1 AUTHOR

Inverse inc. <info@inverse.ca>

=head1 COPYRIGHT

Copyright (C) 2005-2015 Inverse inc.

=head1 LICENSE

This program is free software; you can redistribute it and::or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301,
USA.

=cut
1;

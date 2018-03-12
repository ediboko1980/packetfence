#!/usr/bin/perl

=head1 NAME

Nodes

=cut

=head1 DESCRIPTION

unit test for Nodes

=cut

use strict;
use warnings;
#
use lib '/usr/local/pf/lib';

BEGIN {
    #include test libs
    use lib qw(/usr/local/pf/t);
    #Module for overriding configuration paths
    use setup_test_config;
}

use Test::More tests => 4;

#This test will running last
use Test::NoWarnings;
use pf::UnifiedApi::SearchBuilder::Nodes;
use pf::error qw(is_error);
use pf::constants qw($ZERO_DATE);
use pf::dal::node;
my $dal = "pf::dal::node";

my $sb = pf::UnifiedApi::SearchBuilder::Nodes->new();

is_deeply(
    [ $sb->make_columns( { dal => $dal, fields => [ 'mac', 'ip4log.ip', 'locationlog.ssid', 'locationlog.port' ] } ) ],
    [ 200, [ 'mac', 'ip4log.ip', 'locationlog.ssid', 'locationlog.port'] ],
    'Return the joined columns'
);

{
    my ($status, $col) = $sb->make_columns({ dal => $dal,  fields => [qw(mac $garbage ip4log.ip)] });
    ok(is_error($status), "Do no accept invalid columns");
}

is_deeply(
    [ $sb->make_from( {dal => $dal,  fields => [ 'mac', 'ip4log.ip', 'locationlog.ssid', 'locationlog.port' ] } ) ],
    [
        200,
        [
            -join => 'node',
            @pf::UnifiedApi::SearchBuilder::Nodes::IP4LOG_JOIN,
            @pf::UnifiedApi::SearchBuilder::Nodes::LOCATION_LOG_JOIN,
        ]
    ],
    'Return the joined columns'
);

=head1 AUTHOR

Inverse inc. <info@inverse.ca>

=head1 COPYRIGHT

Copyright (C) 2005-2018 Inverse inc.

=head1 LICENSE

This program is free software; you can redistribute it and/or
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

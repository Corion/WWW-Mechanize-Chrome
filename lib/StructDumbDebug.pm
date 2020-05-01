package StructDumbDebug;
use strict;
use IO::Async::Loop;

use Net::Async::WebSocket::Client;
Net::Async::WebSocket::Client->VERSION(0.12); # fixes some errors with masked frames

our $VERSION = '0.50';

1;

#!/usr/bin/perl
# Creator: Tyler S Johnson
# Email:   jtylers@byu.edu
# Date:    July 29, 2015
# Usage: ./check_krb5_admin_server.pl hostname
# Description:
#       This script determines whether
#       the kerbmaster is functioning
# Reference: http://web.mit.edu/kerberos/krb5-1.12/doc/admin/admin_commands/kadmin_local.html

use strict;
use warnings;
use Getopt::Long qw(:config ignore_case);

my $help_text = 
"usage:  ./check_krb5_admin_server.pl [options]\n
[options] are any of the following:
        -?,--help
        -d,--domain domain.name.com   {default is the current host's domain}
        -k,--keytab /path/to/keytab   {default is /etc/krb5.keytab}
        -o,--port [port_number]       {default is 749}
        -p,--principal principal_name {default is host/[current hostname].domain}
        -r,--realm REALM.NAME         {default is the current host's domain ALL CAPS}
        -s,--server name_or_ip        {defualt is kerbmaster}
        -v,--verbose\n";

#Handle command line options
my ( $help,$domain,$keytab,$port,$principal,$realm,$server,$verbose ) = "";
GetOptions (    'help|?'                => \$help,
                'd|domain=s{1}'         => \$domain,
                'k|keytab=s{1}'         => \$keytab,
                'o|port=s{1}'           => \$port,
                'p|principal=s{1}'      => \$principal,
                'r|realm=s{1}'          => \$realm,
                's|server=s{1}'         => \$server,
                'v|verbose'             => \$verbose )
or die $help_text;

if ($help) {
        print $help_text;
        exit(0);
}

#Set defaults
my $user = getpwuid( $< );
chomp(my $hostname= `hostname`);
chomp($domain   ||= `hostname -d`);
$keytab         ||= "/etc/krb5.keytab";
$port           ||= "749";
$principal      ||= "host/$hostname.$domain";
$realm          ||= uc$domain;
$server         ||= "kerbmaster";

my $address = "";
my $error = "";
my $file = "";
if ( $server =~ /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/ ){
        $address = $server;
} else {
        $address = "$server.$domain";
}

#Verbosity is for testing only
if ($verbose){
        print "hostname:  $hostname\n"
             ."domain:    $domain\n"
             ."keytab:    $keytab\n"
             ."port:      $port\n"
             ."principal: $principal\n"
             ."realm:     $realm\n"
             ."server:    $server\n\n";
        `kadmin -kt $keytab -p $principal -r $realm -s $address:$port -q \"q\"`;
        exit (3);
} else {
        #Check Kadmin with Nagios
        if ($user eq "root"){
                $file = "/$user/check_admin_server.tmp";
        } else {
                $file = "/home/$user/check_admin_server.tmp";
        }
        system" touch $file";

        eval {
                local $SIG{ALRM} = sub {
                                print "Timeout while connecting to $server\n";
                                exit(2);
                        };
                #Timeout after 5 seconds
                alarm 5;
                `kadmin -kt $keytab -p $principal -r $realm -s $address:$port -q \"q\" > /dev/null 2> $file`;
                alarm 0;
        };

        #Filter the output
        open(my $input, "<", $file) or die $!;
                while( <$input> ){
                        ($error) = $_ =~ /^kadmin:\s+(.*)while/;
                }
        close $input;
        system "rm $file";

        #Report status
        if (!$error){
                print "KADMIN OK\n";
                exit (0);#OK
        } elsif ($error =~ /failure/){
                print "$error\n";
                exit (1);#Critical
        } elsif ($error =~ /Permission denied/){
                print "$user doesn't have access to $keytab\n";
                print "recomended action, run:\n";
                print "# chmod 460 /etc/krb5.keytab\n";
                print "# chown $user $keytab\n";
                exit (2);#Warning
        } elsif ($error =~ /Bad/){
                print "$error\n";
                exit (2);#Warning
        } elsif ($error =~ /Unsupported/){
                print "Incorrect version number for $principal in $keytab\n";
                exit (2);#Warning
        } elsif ($error =~ /No such/){
                print "$keytab does not exist\n";
                exit (2);#Warning
        } elsif ($error =~ /Missing/){
                print "$error\n";
                exit (2);#Warning
        } else {
                print "$error\n";
                exit (3);#Unkown
        }
}

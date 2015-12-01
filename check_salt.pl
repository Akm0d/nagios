#!/usr/bin/perl
# Creator: Tyler S Johnson
# Email:   jtylers@byu.edu
# Date:    November 30, 2015
# Usage: ./check_salt.pl
# Description: This script will parse the /srv/salt/salt-master-nagios.txt file 
# Make sure that the directory exists before running this script

use strict;
use warnings;
# Get command line options
use Getopt::Long qw(:config ignore_case);
# Get the difference between two dates
use Date::Parse;

# Help text message
my $help_text =
"usage:  ./check_salt.pl [options]\n
[options] are any of the following:
        -?,--help
        -v,--verbose\n";

# Error message
my $Requires = "\nCRITICAL: Cannot find the file \"/srv/salt/scripts/salt-master-nagios.txt\"\n
There should be a 15-minutely on the salt master that does the following:
#!/bin/bash
START_TIME=\$SECONDS # Get the seconds from the current date
date > /srv/salt/scripts/salt-master-nagios.txt; # get the current date and clear output file
salt \* test.ping >> /srv/salt/scripts/salt-master-nagios.txt; # ping all minions
ELAPSED_TIME=$((\$SECONDS - \$START_TIME)); # get elapsed time
echo \$ELAPSED_TIME >> /srv/salt/scripts/salt-master-nagios.txt; # append the elapsed time to output
scp /srv/salt/scripts/salt-master-nagios.txt nagios:/srv/salt/ > /dev/null; # send data to nagios\n\n";

#Handle command line options
my ( $help,$verbose ) = "";
GetOptions (    'help|?'                => \$help,
                'v|verbose'             => \$verbose
)
or die $help_text;

if ($help) {
        print $help_text;
        exit(0);
}

# This is the file to be parsed
my $file = "/srv/salt/salt-master-nagios.txt";
# Open the file
open(FILE,"< $file") or die $Requires;
# Store the file in an array called @lines
my @lines;
while( <FILE>) {
        push(@lines,$_);
}

# The first line of the file will have the date file was generated
chomp(my $file_date = shift @lines);
# The last line of the file will have the latency in seconds
chomp(my $latency = pop @lines);
# Get the current date and time
chomp(my $date = `date +"%H:%M:%S"`);

my $limit = 20; # the number of minutes between checks
# Find the difference in seconds between the two dates
my $date_diff = str2time($date) - str2time($file_date);
if ($date_diff > ($limit * 60)){ # Turn the limit in minutes to seconds
        my @seconds = gmtime($date_diff); # Convert seconds to human readable time
        printf("UNKNOWN: The master hasn't sent new data in %2d days %2d hours %2d minutes  and %2d seconds\n"
                ,@seconds[7,2,1,0]); # print out a human readable statement
        exit 3;
}

# Iterate through the ping list two items at a time
my $unreachable = ""; # Minions that pinged false
my $first_pass  = 1; # True
my $plural      = 0; # Keep track of whether or not "is" or "are" should be used
while (scalar(@lines) > 0){
        chomp(my $minion = shift(@lines)); # the first item is the server name
        # If the first item
        if ($minion =~ "The master is not responding" && $first_pass){
                # Exit with a critical status and report latency
                print "CRITICAL: Master didn't respond after $latency seconds\n";
                exit 2;
        }
        chomp(my $reachable = shift(@lines)); # the second item is True/False
        # Make a list of unreachable minions
        if ($reachable =~ "Not connected"){
                if (!$unreachable){ # if the string is empty
                        chop($unreachable = $minion);
                } else { # concatenate to existing string
                        $plural = 1;#
                        chop($unreachable = $unreachable . ", $minion");
                }
        }
        $first_pass = 0; # False
}

# Use the correct verb in printout statements
if ($plural){
        $plural = "are";
} else {
        $plural = "is";
}

if ($unreachable){
        print "WARNING: $unreachable $plural disconnected or unreachable after $latency seconds\n";
        # Release a warning message with a list of unreachable minions
        exit 1;
} else {
        print "OK: All minions were reached within $latency seconds\n";
        exit 0;
}

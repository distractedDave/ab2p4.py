#!/usr/bin/perl -w

=pod

=head1 NAME

B<p42svn> - dump Perforce repository in Subversion portable dump/load format.

=head1 SYNOPSIS

B<p42svn> [I<options>] [B<--branch> I<p4_branch_spec=svn_path>] ...

=head1 OPTIONS

=over 8

=item B<--help>

Print detailed help message and exit.

=item B<--usage>

Print brief usage message and exit.

=item B<--debug>

Print debug messages to STDERR.

=item B<--verbose>

Print status messages to STDERR.

=item B<--dry-run>

Don't actually retrieve file data, but go through the motions. This is
useful for checking depot validity and for debugging.

=item B<--changes> I<list>

Specifies which changelists to process.  The list can contain a list of
numbers and ranges separated by commas, such as 12,39-45,68.

=item B<--branch> I<p4_depot_spec=svn_path>

Specify mapping of Perforce branch to repository path.  Takes an
argument of the form p4_depot_spec=svn_path.  Multiple branch mappings
may be specified, but at least one is required.

=item B<--munge-keywords|--nomunge-keywords>

Do/don't convert Perforce keywords to their Subversion equivalent.
Default is not to perform keyword conversion.

=item B<--convert-eol|--noconvert-eol>

Do/don't set the svn:eol-style property for Perforce types text/unicode.
Default is not to set the svn:eol-style property.

=item B<--parse-mime-types|--noparse-mime-types>

Do/don't attempt to parse content MIME type and add svn:mime-type
property.  Default is not to parse MIME types.

=item B<--mime-magic-path> I<path>

Specify path of MIME magic file, overriding the default
F</usr/share/file/magic.mime>.  Ignored unless B<--parse-mime-types>
is true.

=item B<--delete-empty-dirs|--nodelete-empty-dirs>

Do/don't delete the parent directory when the last file/directory it
contains is deleted.  Default is to delete empty directories.

=item B<--user> I<name>

Specify Perforce username; this overrides $P4USER, $USER, and
$USERNAME in the environment.

=item B<--client> I<name>

Specify Perforce client; this overrides $P4CLIENT in the environment
and the default, the hostname.

=item B<--port> I<[host:]port>

Specify Perforce server and port; this overrides $P4PORT in the
environment and the default, perforce:1666.

=item B<--password> I<token>

Specify Perforce password; this overrides $P4PASSWD in the
environment.

=item B<--charset> I<token>

Specify Perforce charset; this overrides $P4CHARSET in the
environment

=back

=head1 DESCRIPTION

B<p42svn> connects to a Perforce server and examines changelists
affecting the specified repository branch(es).  Records reflecting
each change are written to STDOUT in Subversion portable dump/load
format.  Each Perforce changelist corresponds to a single Subversion
revision.  Changelists restricted to files outside the specified
Perforce branch(es) are ignored.

Migration of a Perforce depot to Subversion can thus be achieved in
two easy steps:

=over 4

=item C<svnadmin create /path/to/repository>

=item C<p42svn --branch //depot/projectA=trunk/projectA | svnadmin load /path/to/repository>

=back

It is also possible to specify multiple branch mappings to change the
repository layout when migrating, for example:

=over 4

=item C<p42svn --branch //depot/projectA/devel=projectA/trunk --branch
//depot/projectA/release-1.0=projectA/tags/release1.0>

=back

=head1 REQUIREMENTS

This program requires the Perforce Perl API, which is available for
download from
E<lt>http://www.perforce.com/perforce/loadsupp.html#apiE<gt>.

Version 0.16 has been tested By Ray Miller against version 1.2587 of the P4 module built
against release 2002.2 of the Perforce API.

Versions 0.16, 0.17, and 0.18 have been tested by Dimitri Papadopoulos-Orfanos against
version 3.4804 of the P4 module built against release 2005.2 of the Perforce API.

Version 0.19 has been tested by Dimitri Papadopoulos-Orfanos against version 3.5708 of
the P4 module built against release 2006.1 of the Perforce API.

Version 0.21 has been tested by Dimitri Papadopoulos-Orfanos against version 2008.2 of
the Perforce Perl API and the Perforce C/C++ API.

=head1 VERSION

This is version 0.21.

=head1 AUTHOR

Ray Miller E<lt>ray@sysdev.oucs.ox.ac.ukE<gt>.

=head1 BUGS

Please report any bugs to the issue tracker
E<lt>http://p42svn.tigris.org/servlets/ProjectIssuesE<gt>.

Accuracy of determined MIME types is dependent on your system's MIME
magic data.  This program defaults to using data in
F</usr/share/file/magic.mime>.  This location appears to comply with
the Filesystem Hierarchy Standard (FHS) 2.3, although it may differ
from system to system in practice.

The B<--changes> option has known bugs. Fixing it requires a major
rewrite and has been postponed.

=head1 COPYRIGHT

Copyright (C) 2006-2009 Commissariat a l'Energie Atomique

Copyright (C) 2003-2006 University of Oxford

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
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

=cut

use strict;
use warnings;

use P4;
use Data::Dumper;
use Date::Format;
use Digest::MD5 qw(md5_hex);
use File::MMagic;
use Getopt::Long;
use Pod::Usage;

use constant MIME_MAGIC_PATH => '/usr/share/file/magic.mime';
use constant SVN_FS_DUMP_FORMAT_VERSION => 1;
use constant SVN_DATE_TEMPLATE => '%Y-%m-%dT%T.000000Z';

our (%rev_map, %dir_seen, %dir_usage, @deleted_files, @ranges);

our %KEYWORD_MAP = ('Author'   => 'LastChangedBy',
		    'Date'     => 'LastChangedDate',
		    'Revision' => 'LastChangedRevision',
		    'File'     => 'HeadURL',
		    'Id'       => 'Id');

use constant OPT_SPEC => qw(help usage debug verbose dry-run changes=s
                            branch=s% delete-empty-dirs! munge-keywords!
			    convert-eol! parse-mime-types! mime-magic-path=s
			    user=s client=s port=s password=s charset=s);

our %options = ('help'              => 0,
		'usage'             => 0,
		'debug'             => 0,
		'verbose'           => 0,
		'dry-run'           => 0,
		'changes'           => undef,
		'delete-empty-dirs' => 1,
		'munge-keywords'    => 0,
		'convert-eol'       => 0,
		'parse-mime-types'  => 0,
		'mime-magic-path'   => MIME_MAGIC_PATH,
		'branch'            => {});

########################################################################
# Identify Perforce Perl API version, so that we can adapt to the API.
########################################################################

my $p4perl_version = undef;

if (defined $P4::VERSION) {
    # This is original version of P4Perl from Tony Smith's page.
    # Latest version 3.6001 has been written for P4API 2007.2 or earlier.
    $p4perl_version = $P4::VERSION;
    $p4perl_version =~ s/^\s+//;
    $p4perl_version =~ s/\s+$//;
} else {
    # This the new version of the Perforce Perl API from the FTP server.
    # The Perforce Perl API is now released together with Perforce,
    # starting with 2007.3.
    $p4perl_version = P4::Identify();
    if ($p4perl_version =~ /P4PERL\/[^\/]+\/(\d+\.\d+)[^\/]*\/\d+/s) {
	$p4perl_version = $1;
    }
}

my $p42svn_version = 0.21;

########################################################################
# Print debugging messages when debug option is set.
########################################################################

sub debug {
    return unless $options{'debug'};
    print STDERR @_;
}

sub verbose {
    return unless $options{'verbose'} or $options{'debug'};
    print STDERR @_;
}

########################################################################
# Helper routines for option validation.
########################################################################

sub is_valid_depot {
    my $depot = shift;
    return $depot =~ m{^//([^/]+/?)*$};
}

sub is_valid_svnpath {
    my $path = shift;
    return $path =~ m{^/?([^/]+/?)*$};
}

########################################################################
# Helper routines for handling changelist ranges.
########################################################################

sub is_in_range {
    my $change = shift;
    return 1 unless @ranges;
    foreach (@ranges) {
	$_->[0] <= $change && $change <= $_->[1] && return 1;
    }
    return 0;
}

########################################################################
# Process command-line options.
########################################################################

sub process_options {
    GetOptions(\%options, OPT_SPEC) and @ARGV == 0
	or pod2usage(-exitval => 2, -verbose => 1);
    pod2usage(-exitval => 1, -verbose => 2)
	if $options{'help'};
    pod2usage(-exitval => 1, -verbose => 1)
	if $options{'usage'};
    pod2usage(-exitval => 2, -verbose => 0,
              -message => "Must specify at least one branch")
	unless keys %{$options{'branch'}};

    # Build list of [start,end] pairs (changelist ranges to process)
    if ($options{'changes'}) {
	foreach (split(/,/,$options{'changes'})) {
	    my @range = split(/-/,$_);
	    pod2usage(-exitval => 3, -verbose => 1,
	              -message => "Invalid range of changelists")
		if (@range > 2);
	    push(@ranges, [int($range[0]),int($range[$#range])]);
	}
    }

    # Validate and sanitize branch specifications
    while (my ($key, $val) = each %{$options{'branch'}}) {
	pod2usage(-exitval => 2, -verbose => 0,
	          -message => "Invalid Perforce depot specification: \"$key\"")
	    unless is_valid_depot($key);
	pod2usage(-exitval => 2, -verbose => 0,
	          -message => "Invalid Subversion repository path \"$val\"")
	    unless is_valid_svnpath($val);
	if ($val =~ m{.+[^/]$}) {
	    $options{'branch'}{$key} .= "/";
	}
	if ($key =~ m{[^/]$}) {
	    $options{'branch'}{"$key/"} = $options{'branch'}{$key};
	    delete $options{'branch'}{$key};
	}
	debug("process_options: branch $key => $val\n");
    }
}

########################################################################
# Does Perforce file lie in a branch we're processing?
######################################################################## 

sub is_wanted_file {
    my $filespec = shift;
    debug("is_wanted_file: $filespec\n");
    foreach (keys %{$options{'branch'}}) {
	debug("is_wanted_file: considering $_\n");
	return 1 if $filespec =~ /^$_/;
    }
    debug("is_wanted_file: ignoring $filespec\n");
    return 0;
}

########################################################################
# Map Perforce depot spec to Subversion path.
########################################################################

sub depot2svnpath {
    my $depot = shift;
    my $branches = $options{'branch'};
    my $key = undef;
    foreach (sort {length($a) <=> length($b)} keys %$branches) {
	next unless $depot =~ /^$_/;
	$key = $_;
    }
    return undef unless $key;
    my $svnpath = $depot;
    $svnpath =~ s/^$key/$branches->{$key}/;
    $svnpath =~ s/%40/@/;
    $svnpath =~ s/%23/#/;
    $svnpath =~ s/%2a/*/;
    $svnpath =~ s/%25/%/;
#    debug("depot2svnpath: $depot => $svnpath\n");
    return $svnpath;
}

########################################################################
# Helper routines for Perforce file types.
########################################################################

sub p4_has_keyword_expansion {
    my $type = shift;
    return $type =~ /^k/ || $type =~ /\+.*k/;
}

sub p4_has_executable_flag {
    my $type = shift;
    return $type =~ /^[cku]?x/ || $type =~ /\+.*x/;
}

sub p4_has_text_flag {
    my $type = shift;
    return $type =~ /text|unicode/;
}

########################################################################
# Return property list based on Perforce file type and (optionally)
# content MIME type.
########################################################################

my $mmagic;

sub properties {
    my ($type, $content_ref) = @_;
    my @properties;
    if (p4_has_keyword_expansion($type)) {
	push @properties, 'svn:keywords' => join(' ', values %KEYWORD_MAP);
    }
    if (p4_has_executable_flag($type)) {
	push @properties, 'svn:executable' => 'on';
    }
    if ($options{'convert-eol'} && p4_has_text_flag($type)) {
	push @properties, 'svn:eol-style' => 'native';
    }
    if ($options{'parse-mime-types'}) {
	unless ($mmagic) {
	    $mmagic = File::MMagic->new($options{'mime-magic-path'})
	      or die "Unable to open MIME magic file "
	        . $options{'mime-magic-path'} . $!;
	}
	my $mtype = $mmagic->checktype_contents($$content_ref);
	push(@properties, 'svn:mime-type' => $mtype) if $mtype;
    }
    return \@properties;
}

########################################################################
# Replace Perforce keywords in file content with equivalent Subversion
# keywords.
########################################################################

sub munge_keywords {
    return unless $options{'munge-keywords'};
    my $content_ref = shift;
    while (my ($key, $val) = each %KEYWORD_MAP) {
	$$content_ref =~ s/\$$key(?\:[^\$\n]*)?\$(\W)/\$$val\$$1/g;
    }
}

########################################################################
# Return parent directories of a path
########################################################################

sub parent_directories {
    my $path = shift;
    my @components;
    my $offset = 0;
    while ((my $ix = index($path, '/', $offset)) >= 0) {
	$offset = $ix + 1;
	push @components, substr($path, 0, $offset);
    }
    return @components;
}

########################################################################
# Return parent directory of a path
########################################################################

sub parent_directory {
    my $path = shift;
    (my $parent_dir = $path) =~ s|[^/]+/?$||;
    return $parent_dir;
}

########################################################################
# Convert Subversion property list to string.
########################################################################

sub svn_props2string {
    my $properties = shift;
    my $result;
    if (defined $properties) {
	while (my ($key, $val) = splice(@$properties, 0, 2)) {
	    $result .= sprintf("K %d\n%s\n", length($key), $key);
	    $result .= sprintf("V %d\n%s\n", length($val), $val);
	}
    }
    $result .= 'PROPS-END';
    return $result;
}

########################################################################
# Routines to print Subversion records.
########################################################################

sub svn_dump_format_version {
    my ($version) = @_;
    print "SVN-fs-dump-format-version: $version\n\n";
}

sub svn_revision {
    my ($revision, $properties) = @_;
    my $ppty_txt = svn_props2string($properties);
    my $ppty_len = length($ppty_txt) + 1;
    print <<EOT;
Revision-number: $revision
Prop-content-length: $ppty_len
Content-length: $ppty_len

$ppty_txt

EOT
}

sub svn_add_dir {
    my ($path, $properties) = @_;
    $dir_usage{parent_directory($path)}++;
    my $ppty_txt = svn_props2string($properties);
    my $ppty_len = length($ppty_txt) + 1;
    print <<EOT;
Node-path: $path
Node-kind: dir
Node-action: add
Prop-content-length: $ppty_len
Content-length: $ppty_len

$ppty_txt

EOT
}

sub svn_add_file {
    my ($path, $properties, $text) = @_;
    $dir_usage{parent_directory($path)}++;
    my $ppty_txt = svn_props2string($properties);
    my $ppty_len = length($ppty_txt) + 1;
    my $text_len = length($text);
    my $text_md5 = md5_hex($text);
    my $content_len = $ppty_len + $text_len;
    print <<EOT;
Node-path: $path
Node-kind: file
Node-action: add
Text-content-length: $text_len
Text-content-md5: $text_md5
Prop-content-length: $ppty_len
Content-length: $content_len

$ppty_txt
$text

EOT
}

sub svn_add_symlink {
    my ($path, $properties, $text) = @_;
    push(@$properties, ('svn:special','*'));
    $text = "link $text";
    svn_add_file($path, $properties, $text);
}

sub svn_edit_file {
    my ($path, $properties, $text) = @_;
    my $ppty_txt = svn_props2string($properties);
    my $ppty_len = length($ppty_txt) + 1;
    my $text_len = length($text);
    my $text_md5 = md5_hex($text);
    my $content_len = $ppty_len + $text_len;
    print <<EOT;
Node-path: $path
Node-kind: file
Node-action: change
Text-content-length: $text_len
Text-content-md5: $text_md5
Prop-content-length: $ppty_len
Content-length: $content_len

$ppty_txt
$text

EOT
}

sub svn_edit_symlink {
    my ($path, $properties, $text) = @_;
    push(@$properties, ('svn:special','*'));
    $text = "link $text";
    svn_edit_file($path, $properties, $text);
}

sub svn_delete {
    my ($path) = @_;
    $dir_usage{parent_directory($path)}--;

    print <<EOT;
Node-path: $path
Node-action: delete

EOT
}

sub svn_add_copy {
    my ($path, $from_path, $from_rev) = @_;
    $dir_usage{parent_directory($path)}++;
    print <<EOT;
Node-path: $path
Node-kind: file
Node-action: add
Node-copyfrom-rev: $from_rev
Node-copyfrom-path: $from_path

EOT
}

sub svn_replace_copy {
    my ($path, $from_path, $from_rev) = @_;
    print <<EOT;
Node-path: $path
Node-kind: file
Node-action: replace
Node-copyfrom-rev: $from_rev
Node-copyfrom-path: $from_path

EOT
}

sub svn_add_parent_dirs {
    my $svn_path = shift;
    debug("svn_add_parent_dirs: $svn_path\n");
    foreach my $dir (parent_directories($svn_path)) {
	next if ($dir eq '/') or $dir_seen{$dir}++;
#	debug("svn_add_parent_dirs: adding $dir\n");
	svn_add_dir($dir, undef);
    }
}

sub svn_delete_empty_parent_dirs {
    return unless $options{'delete-empty-dirs'} && @_;
    debug("svn_delete_empty_parent_dirs: passed @_\n");

    my @deleted_dirs;
    for (@_) {
	$_ = parent_directory($_) or next;
	debug("svn_delete_empty_parent_dirs: $_ usage $dir_usage{$_}\n");
	if ($dir_usage{$_} == 0 && $dir_seen{$_} > 0) {
	    debug("svn_delete_empty_parent_dirs: deleting $_\n");
	    svn_delete($_);
	    $dir_seen{$_} = 0;
	    push(@deleted_dirs, $_);
	}
    }

    svn_delete_empty_parent_dirs(@deleted_dirs);
}

#########################################################################
# Routines for interacting with Perforce server.
#########################################################################

sub p4_init {
    my $p4 = P4->new();
    $p4->SetUser($options{'user'}) if $options{'user'};
    $p4->SetClient($options{'client'}) if $options{'client'};
    $p4->SetPort($options{'port'}) if $options{'port'};
    $p4->SetPassword($options{'password'}) if $options{'password'};
    $p4->SetCharset($options{'charset'}) if $options{'charset'};
    if ($p4perl_version < 2007.3) {
	$p4->ParseForms();
    } else {
	$p4->SetVersion("p42svn $p42svn_version");
    }
    $p4->Connect() or die "Failed to connect to Perforce server ", $p4->GetPort();
    return $p4;
}

#
# Discard changelists outside of specified branches.
#
sub p4_get_changes {
    my $p4 = p4_init();
    my @changes;

    # Consider only changelists related to the specified branch mappings.
    foreach my $branch (keys %{$options{'branch'}}) {
	debug("p4_get_changes: branch $branch\n");
	push @changes, $p4->Run('changes', $branch . "...");
	die $p4->Errors() if $p4->ErrorCount();
    }
    $p4->Disconnect();

    # Remove duplicates.
    my %seen = map {$_->{'change'} => 1} @changes;

    # Filter out changelists outside of the specified ranges and sort.
    return sort {$a <=> $b} grep {is_in_range $_} keys %seen;
}

sub p4_get_change_details {
    my $change_num = shift;
    debug("p4_get_change_details: $change_num\n");
    my $p4 = p4_init();
    my $change = ($p4->Run('describe', '-s', $change_num))[0];
    my $error_count = $p4->ErrorCount();
    my $errors = $p4->Errors();
    $p4->Disconnect();
    if ($error_count) {
	warn "Skipping $change_num due to errors:\n$errors\n";
	return undef;
    }
    my %result;
    $result{'author'} = $change->{'user'};
    $result{'log'}  = $change->{'desc'};
    $result{'date'} = time2str(SVN_DATE_TEMPLATE, $change->{'time'});
    for (my $i = 0; $i < @{$change->{'depotFile'}}; $i++) {
	my $file = $change->{'depotFile'}[$i];
	my $action = $change->{'action'}[$i];
	my $type = $change->{'type'}[$i];
	if (is_wanted_file($file)) {
	    push @{$result{'actions'}}, {'action' => $action,
	                                 'path' => $file,
	                                 'type' => $type};
	}
    }
    return \%result;
}

# this one is without thread, I think it may cause out-of-memory problem due to concatenation. 
sub p4_get_file_content{
    my $filespec = shift;
    return 'Content placeholder!' if ($options{'dry-run'});
    debug("p4_get_file_content: $filespec\n");
    local $/ = undef;
    my $p4 = p4_init();
    my $result = undef;
    my $content = '';
    $result = $p4->Run('print', $filespec);
    die $p4->Errors() if $p4->ErrorCount();
    if (ref $result eq 'ARRAY') {
        for (my $i = 1; $i < @$result; $i++) {
            $content = $content . $result->[$i];
        }
    }
    $p4->Disconnect();

    return $content;
} 

#
# We have to jump through hoops to get the file content because
# Print() behaves inconsistently.  For text files, it returns an array
# reference, the first element of which is a hash reference with
# details we're not interested in, and remaining elements the file
# content; but for binary files it just returns the hash reference
# and writes the content to STDOUT.  Painful!
#
sub p4_get_file_content_threaded {
    my $filespec = shift;
    return 'Content placeholder!' if ($options{'dry-run'});
    debug("p4_get_file_content: $filespec\n");
    local *P4_OUTPUT;
    local $/ = undef;
    #my $pid = open(P4_OUTPUT, "-|");
    my $pid = pipe_to_fork(*P4_OUTPUT);
    die "Fork failed: $!" unless defined $pid;
    if ($pid == 0) { # child
		my $p4 = p4_init();
		my $result = undef;
		$result = $p4->Run('print', $filespec);
		die $p4->Errors() if $p4->ErrorCount();
		if (ref $result eq 'ARRAY') {
		    for (my $i = 1; $i < @$result; $i++) {
			print $result->[$i];
		    }
	}
	$p4->Disconnect();
	exit 0;
    }
    #
    my $content = <P4_OUTPUT>;
    close(P4_OUTPUT) or die "Close failed: ($?) $!";
    return $content;
}

# REF, http://p42svn.tigris.org/ds/viewMessage.do?dsForumId=4900&dsMessageId=2371906
# REF, http://perldoc.perl.org/perlfork.html#Forking-pipe-open()-not-yet-implemented
sub pipe_to_fork ($) {
    my $parent = shift;
    pipe my $child, $parent or die;
    my $pid = fork();
    die "fork() failed: $!" unless defined $pid;
    if ($pid) {
        close $child;
    }
    else {
        close $parent;
        open(STDIN, "<&=" . fileno($child)) or die;
    }
    $pid;
}

#
# Depending on the version of Perforce, Diff2() may return an
# ARRAY of SCALAR, A HASH, or an ARRAY of HASH.
#
sub p4_files_are_identical {
    my ($src_fspec, $dst_fspec) = @_;
    debug("p4_files_are_identical: @_\n");
    my $p4 = p4_init();
    my $result = $p4->Run('diff2', $src_fspec, $dst_fspec);
    die $p4->Errors() if $p4->ErrorCount();
    if (ref $result eq 'ARRAY') {
	if (ref $result->[0] eq 'HASH') { # Perforce 2006.2
	    $result = $result->[0]->{'status'};
	} elsif (not ref $result->[0] and $result->[0] =~ /===\s*(\w*)\s*$/) { # Perforce 2003.1
	    $result = $1;
	} else {
	    die "Command 'diff2' returns ARRAY containing unexpected item";
	}
    } elsif (ref $result eq 'HASH') {  # Perforce 2005.1
	$result = $result->{'status'};
    } else {
        die "Command 'diff2' returns ", ref $result, ", expected ARRAY or HASH instead";
    }
    debug("p4_files_are_identical: $result\n");
    $p4->Disconnect();
    return $result eq 'identical';
}

#
# If $path was not modified by this $change, return (undef, undef),
# which signals to the caller to ignore this file.  If we are unable,
# for any reason, to determine the source of a branch/integrate,
# return (undef, -n), signalling to the caller to treat this as an
# add/edit.
#
sub p4_get_copyfrom_filerev {
    my ($path, $change) = @_;
    debug("p4_get_copyfrom_filerev: passed $path\@$change\n");
    if ($change > 1 && p4_files_are_identical($path.'@'.$change,
                                              $path.'@'.($change-1))) {
	debug("p4_get_copyfrom_filerev: $path\@$change unchanged\n");
	return (undef, undef);
    }
    my $p4 = p4_init();
    my $result = $p4->Run('filelog', "$path\@$change");
    die $p4->Errors() if $p4->ErrorCount();
    if (ref $result eq 'ARRAY') { # Perforce 2006.2
	unless (ref $result->[0] eq 'HASH') {
	    die "Command 'filelog' returns an ARRAY missing a HASH";
	}
	$result = $result->[0];   # Now in the Perforce 2005.1 case
    }
    if (ref $result eq 'HASH') {  # Perforce 2005.1
	unless ($result->{'how'}) {
	    debug("p4_get_copyfrom_filerev: returning undef#-1\n");
	    $p4->Disconnect();
	    return (undef, -1);
	}
	my $i;
	for ($i = 0; $i < @{$result->{'how'}->[0]}; $i++) {
	    last if $result->{'how'}->[0][$i] =~ /from$/;
	}
	if ($i > $#{$result->{'how'}->[0]}) {
	    debug("p4_get_copyfrom_filerev: returning undef#-2)\n");
	    $p4->Disconnect();
	    return (undef, -2);
	}
	my $copyfrom_path = $result->{'file'}[0][$i];
	my $copyfrom_rev  = $result->{'erev'}[0][$i];
	$p4->Disconnect();
	debug("p4_get_copyfrom_filerev: returning $copyfrom_path$copyfrom_rev\n");
	return ($copyfrom_path, $copyfrom_rev);
    }
    die "Command 'filelog' returns ", ref $result, ", expected ARRAY or HASH instead";
}

########################################################################
# Return Subversion revision of Perforce file at given revision.
########################################################################

sub p4_file2svnrev {
    my ($file, $rev) = @_;
    debug("p4_file2svnrev: $file$rev\n");
    my $p4 = p4_init();
    my $result = $p4->Run('filelog', $file . $rev);
    die $p4->Errors() if $p4->ErrorCount();
    if (ref $result eq 'ARRAY') { # Perforce 2006.2
	unless (ref $result->[0] eq 'HASH') {
	    die "Command 'filelog' returns an ARRAY missing a HASH";
	}
	$result = $result->[0];   # Now in the Perforce 2005.1 case
    }
    if (ref $result eq 'HASH') {  # Perforce 2005.1
	my $change = shift @{$result->{'change'}};
	$p4->Disconnect();
	if (is_in_range($change)) {
	    unless (defined $rev_map{$change}) {
		die "Can't map $file$rev to Subversion revision";
	    }
	    debug("p4_file2svnrev: p4 $change to svn r$rev_map{$change}\n");
	    return $rev_map{$change};
	} else {
	    debug("p4_file2svnrev: $change is not within specified changelists\n");
	    return -1;
	}
    }
    die "Command 'filelog' returns ", ref $result, ", expected ARRAY or HASH instead";
}

########################################################################
# Routines for converting Perforce actions to Subversion dump/restore
# records.
########################################################################

sub p4add2svn {
    my ($path, $type, $change) = @_;
    debug("p4add2svn: $path\@$change\n");
    my $svn_path = depot2svnpath($path)
      or die "Unable to determine SVN path for $path\n";
    svn_add_parent_dirs($svn_path);
    my $content = p4_get_file_content("$path\@$change");
    munge_keywords(\$content) if p4_has_text_flag($type);
    chop $content if $type =~ /symlink$/;
    my $properties = properties($type, \$content);
    if ($type =~ /symlink$/) {
        svn_add_symlink($svn_path, $properties, $content);
    } else {
        svn_add_file($svn_path, $properties, $content);
    }
}

sub p4delete2svn {
    my ($path, $type, $change) = @_;
    debug("p4delete2svn: $path\@$change\n");
    my $svn_path = depot2svnpath($path)
      or die "Unable to determine SVN path for $path\n";
    svn_delete($svn_path);
    push @deleted_files, $svn_path;
}

sub p4edit2svn {
    my ($path, $type, $change) = @_;
    debug("p4edit2svn: $path\@$change\n");
    my $svn_path = depot2svnpath($path)
      or die "Unable to determine SVN path for $path\n";
    my $content = p4_get_file_content("$path\@$change");
    munge_keywords(\$content) if p4_has_text_flag($type);
    chop $content if $type =~ /symlink$/;
    my $properties = properties($type, \$content);
    if ($type =~ /symlink$/) {
        svn_edit_symlink($svn_path, $properties, $content);
    } else {
        svn_edit_file($svn_path, $properties, $content);
    }
}

sub p4branch2svn {
    my ($path, $type, $change) = @_;
    debug("p4branch2svn: $path\@$change\n");
    my $svn_path = depot2svnpath($path)
      or die "Unable to determine SVN path for $path\n";
    my ($from_path, $from_rev) = p4_get_copyfrom_filerev($path, $change);
    debug("p4branch2svn: switch to $from_path\@$from_rev\n");
    unless ($from_path) {
	if ($from_rev) {
	    p4add2svn($path, $type, $change);
	} else {
	    warn "Ignoring $path\@$change\n";
	}
	return;
    }
    unless (p4_files_are_identical($from_path.$from_rev, "$path\@$change")) {
	p4add2svn($path, $type, $change);
	return;
    }
    svn_add_parent_dirs($svn_path);
    my $svn_from_path = depot2svnpath($from_path);
    if ($svn_from_path) {
	# Source is within specified branches
	my $svn_from_rev = p4_file2svnrev($from_path, $from_rev);
	if ($svn_from_rev > 0) {
	    # Initial changelist falls within specified changelists
	    svn_add_copy($svn_path, $svn_from_path, $svn_from_rev);
	    return;
	}
    }
    # Outside of specified branches or changelists: treat as add
    my $content = p4_get_file_content($from_path . $from_rev);
    munge_keywords(\$content) if p4_has_text_flag($type);
    my $properties = properties($type, \$content);
    svn_add_file($svn_path, $properties, $content);
}

sub p4integrate2svn {
    my ($path, $type, $change) = @_;
    debug("p4integrate2svn: $path\@$change\n");
    my $svn_path = depot2svnpath($path)
      or die "Unable to determine SVN path for $path\n";
    my ($from_path, $from_rev) = p4_get_copyfrom_filerev($path, $change);
    if ($from_path) {
	debug("p4integrate2svn: switch to $from_path\@$from_rev\n");
    } else {
	debug("p4integrate2svn: uninitialized \$from_path: empty integration?\n");
	if ($from_rev) {
	    p4edit2svn($path, $type, $change);
	} else {
	    warn "Ignoring $path\@$change\n";
	}
	return;
    }
    unless (p4_files_are_identical($from_path.$from_rev, "$path\@$change")) {
	p4edit2svn($path, $type, $change);
	return;
    }
    my $svn_from_path = depot2svnpath($from_path);
    if ($svn_from_path) {
	# Source is within specified branches
	my $svn_from_rev  = p4_file2svnrev($from_path, $from_rev);
	if ($svn_from_rev > 0) {
	    # Initial changelist falls within specified changelists
	    svn_replace_copy($svn_path, $svn_from_path, $svn_from_rev);
	    return;
	}
    }
    # Outside of specified branches or changelists: treat as edit
    my $content = p4_get_file_content($from_path . $from_rev);
    munge_keywords(\$content) if p4_has_text_flag($type);
    my $properties = properties($type, \$content);
    svn_edit_file($svn_path, $properties, $content);
}

sub p4purge2svn {
    my ($path, $type, $change) = @_;
    debug("p4purge2svn: $path\@$change\n");
    my $svn_path = depot2svnpath($path)
	or die "Unable to determine SVN path for $path\n";
    svn_add_parent_dirs($svn_path);
    my $content = "Placeholder for file purged by Perforce.";
    my $properties = properties($type, \$content);
    svn_add_file($svn_path, $properties, $content);
}

########################################################################
# Main processing
########################################################################

process_options();

my %p42svn = ('add'       => \&p4add2svn,
              'delete'    => \&p4delete2svn,
              'edit'      => \&p4edit2svn,
              'branch'    => \&p4branch2svn,
              'integrate' => \&p4integrate2svn,
              'purge'     => \&p4purge2svn);

my $svn_rev = 1;

binmode(STDOUT);
svn_dump_format_version(SVN_FS_DUMP_FORMAT_VERSION);
foreach my $change_num (p4_get_changes()) {
    my $details = p4_get_change_details($change_num);
    next unless defined $details;
    my @properties = ('svn:log'    => $details->{'log'},
                      'svn:author' => $details->{'author'},
                      'svn:date'   => $details->{'date'});
    @deleted_files = ();
    verbose("p4 $change_num to svn r$svn_rev\n");
    svn_revision($svn_rev, \@properties);
    $rev_map{$change_num} = $svn_rev++;
    foreach (@{$details->{'actions'}}) {
	if (defined $p42svn{$_->{'action'}}) {
	    $p42svn{$_->{'action'}}->($_->{'path'}, $_->{'type'}, $change_num);
	} else {
	    warn "Action $_->{'action'} not recognized "
	      ."($_->{'path'}\@$change_num)\n";
	}
    }
    #
    # This must be done last in case files are both created and
    # deleted in the same directory in the course of a single changelist.
    #
    svn_delete_empty_parent_dirs(@deleted_files);
}

verbose("Completed!\n");



# ###########################################################################
# example:
# perl p42svn.pl --branch //depot/projectA=trunk/projectA --debug --user abc
#  --password=123 > projectA.svndmp
# ###########################################################################


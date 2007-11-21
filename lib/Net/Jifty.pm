#!/usr/bin/env perl
package Net::Jifty;
use Moose;
use YAML;
use Encode;
use URI;
use LWP::UserAgent;
use DateTime;
use Email::Address;
use Fcntl qw(:mode);

=head1 NAME

Net::Jifty - interface to online Jifty applications

=head1 VERSION

Version 0.02 released 21 Nov 07

=cut

our $VERSION = '0.02';

=head1 SYNOPSIS

    use Net::Jifty;
    my $j = Net::Jifty->new(site => 'http://mushroom.mu/', cookie_name => 'MUSHROOM_KINGDOM_SID', appname => 'MushroomKingdom', email => 'god@mushroom.mu', password => 'melange');

    # the story begins
    $j->create(Hero => name => 'Mario', job => 'Plumber');

    # find the hero whose job is Plumber and change his name to Luigi and color
    # to green
    $j->update(Hero => job => 'Plumber', name => 'Luigi', color => 'Green');

    # win!
    $j->delete(Enemy => name => 'Bowser');

=head1 DESCRIPTION

L<Jifty> is a full-stack web framework. It provides an optional REST interface
for applications. Using this module, you can interact with that REST
interface to write client-side utilities.

You can use this module directly, but you'll be better off subclassing it, such
as what we've done for L<Net::Hiveminder>.

=cut

has site => (
    is            => 'rw',
    isa           => 'Str',
    required      => 1,
    documentation => "The URL of your application",
);

has cookie_name => (
    is            => 'rw',
    isa           => 'Str',
    required      => 1,
    documentation => "The name of the session ID cookie. This can be found in your config under Framework/Web/SessinCookieName",
);

has appname => (
    is            => 'rw',
    isa           => 'Str',
    required      => 1,
    documentation => "The name of the application, as it is known to Jifty",
);

has email => (
    is            => 'rw',
    isa           => 'Str',
    documentation => "The email address to use to log in",
);

has password => (
    is            => 'rw',
    isa           => 'Str',
    documentation => "The password to use to log in",
);

has sid => (
    is  => 'rw',
    isa => 'Str',
    documentation => "The session ID, from the cookie_name cookie. You can use this to bypass login",
    trigger => sub {
        my $self = shift;

        my $uri = URI->new($self->site);
        $self->ua->cookie_jar->set_cookie(0, $self->cookie_name,
                                          $self->sid, '/',
                                          $uri->host, $uri->port,
                                          0, 0, undef, 1);
    },
);

has ua => (
    is      => 'rw',
    isa     => 'LWP::UserAgent',
    default => sub {
        my $args = shift;

        my $ua = LWP::UserAgent->new;

        $ua->cookie_jar({});

        # Load the user's proxy settings from %ENV
        $ua->env_proxy;

        return $ua;
    },
);

has config_file => (
    is            => 'rw',
    isa           => 'Str',
    default       => "$ENV{HOME}/.jifty",
    documentation => "The place to look for the user's config file",
);

has use_config => (
    is      => 'rw',
    isa     => 'Bool',
    default => 0,
    documentation => "Whether or not to use the user's config",
);

has config => (
    is      => 'rw',
    isa     => 'HashRef',
    default => sub { {} },
    documentation => "Storage for the user's config",
);

=head2 BUILD

Each L<Net::Jifty> object will do the following upon creation:

=over 4

=item Read config

..but only if you C<use_config> is set to true.

=item Log in

..unless a sid is available, in which case we're already logged in.

=back

=cut

sub BUILD {
    my $self = shift;

    $self->load_config
        if $self->use_config && $self->config_file;

    $self->login
        unless $self->sid;
}

=head2 login

This assumes your site is using L<Jifty::Plugin::Authentication::Password>.
If that's not the case, override this in your subclass.

This is called automatically when each L<Net::Jifty> object is constructed
(unless a session ID is passed in).

=cut

sub login {
    my $self = shift;

    return if $self->sid;

    confess "Unable to log in without an email and password."
        unless $self->email && $self->password;

    confess 'Your email did not contain an "@" sign. Did you accidentally use double quotes?'
        if $self->email !~ /@/;

    my $result = $self->call(Login =>
                                address  => $self->email,
                                password => $self->password);

    confess "Unable to log in."
        if $result->{failure};

    $self->get_sid;
    return 1;
}

=head2 call Action, Args

This uses the Jifty "web services" API to perform an action. This is NOT the
REST interface, though it resembles it to some degree.

This module currently only uses this to log in.

=cut

sub call {
    my $self    = shift;
    my $action  = shift;
    my %args    = @_;
    my $moniker = 'fnord';

    my $res = $self->ua->post(
        $self->site . "/__jifty/webservices/yaml",
        {   "J:A-$moniker" => $action,
            map { ( "J:A:F-$_-$moniker" => $args{$_} ) } keys %args
        }
    );

    if ( $res->is_success ) {
        return YAML::Load( Encode::decode_utf8($res->content) )->{$moniker};
    } else {
        confess $res->status_line;
    }
}

=head2 method Method, URL[, Args]

This will perform a GET, POST, PUT, DELETE, etc using the internal
L<LWP::UserAgent> object.

Your URL may be a string or an array reference (which will have its parts
properly escaped and joined with C</>). Your URL already has
C<http://your.site/=/> prepended to it, and C<.yml> appended to it, so you only
need to pass something like C<model/YourApp.Model.Foo/name>, or
C<[qw/model YourApp.Model.Foo name]>.

This will return the data structure returned by the Jifty application, or throw
an error.

=cut

sub method {
    my $self   = shift;
    my $method = lc(shift);
    my $url    = shift;
    my %args   = @_;

    $url = $self->join_url(@$url)
        if ref($url) eq 'ARRAY';

    # remove trailing /
    $url =~ s{/+$}{};

    my $res;

    if ($method eq 'get' || $method eq 'head') {
        my $uri = $self->site . '/=/' . $url . '.yml';

        if (keys %args) {
            $uri .= '?';
            while (my ($key, $value) = each %args) {
                $uri .= '&' . join '=', map { $self->escape($_) } $key, $value;
            }
            # it's easier than keeping a flag of "did we already append?"
            $uri =~ s/\?&/?/;
        }

        $res = $self->ua->$method($uri);
    }
    else {
        $res = $self->ua->$method(
            $self->site . '/=/' . $url . '.yml',
            \%args
        );
    }

    if ($res->is_success) {
        return YAML::Load( Encode::decode_utf8($res->content) );
    } else {
        confess $res->status_line;
    }
}

=head2 post URL, Args

This will post the arguments to the specified URL. See the documentation for
C<method>.

=cut

sub post {
    my $self = shift;
    $self->method('post', @_);
}

=head2 get URL, Args

This will get the specified URL, using the arguments. See the documentation for
C<method>.

=cut

sub get {
    my $self = shift;
    $self->method('get', @_);
}

=head2 act Action, Args

Perform the specified action, using the specified arguments.

=cut

sub act {
    my $self   = shift;
    my $action = $self->canonicalize_action(shift);

    return $self->post(["action", $action], @_);
}

=head2 create Model, FIELDS

Create a new object of type Model with the FIELDS set.

=cut

sub create {
    my $self = shift;
    my $model = $self->canonicalize_model(shift);

    return $self->post(["model", $model], @_);
}

=head2 delete Model, Key => Value

Find some Model where Key => Value and delete it

=cut

sub delete {
    my $self   = shift;
    my $model  = $self->canonicalize_model(shift);
    my $key    = shift;
    my $value  = shift;

    return $self->method(delete => ["model", $model, $key, $value]);
}

=head2 update Model, Key => Value, FIELDS

Find some Model where Key => Value and set FIELDS on it.

=cut

sub update {
    my $self   = shift;
    my $model  = $self->canonicalize_model(shift);
    my $key    = shift;
    my $value  = shift;

    return $self->method(put => ["model", $model, $key, $value], @_);
}

=head2 read Model, Key => Value

Find some Model where Key => Value and return it.

=cut

sub read {
    my $self   = shift;
    my $model  = $self->canonicalize_model(shift);
    my $key    = shift;
    my $value  = shift;

    return $self->get(["model", $model, $key, $value]);
}

=head2 canonicalize_package Type, Package

Prepends C<$appname.$Type.> to C<$Package> unless it's there already.

=cut

sub canonicalize_package {
    my $self    = shift;
    my $type    = shift;
    my $package = shift;

    my $appname = $self->appname;

    return $package
        if $package =~ /^\Q$appname.$type./;

    return "$appname.$type.$package";
}

=head2 canonicalize_action Action

Prepends C<$appname.Action.> unless it's there already.

=cut

sub canonicalize_action {
    my $self = shift;
    return $self->canonicalize_package('Action', @_);
}

=head2 canonicalize_model Model

Prepends C<$appname.Model.> unless it's there already.

=cut

sub canonicalize_model {
    my $self = shift;
    return $self->canonicalize_package('Model', @_);
}

=head2 get_sid

Retrieves the SID from the LWP::UserAgent object

=cut

sub get_sid {
    my $self = shift;
    my $cookie = $self->cookie_name;

    my $sid;
    $sid = $1
        if $self->ua->cookie_jar->as_string =~ /\Q$cookie\E=([^;]+)/;

    $self->sid($sid);
}

=head2 join_url Fragments

Encodes the fragments and joins them with C</>.

=cut

sub join_url {
    my $self = shift;

    return join '/', map { $self->escape($_) } grep { defined } @_
}

=head2 escape Strings

URI escapes each string

=cut

sub escape {
    my $self = shift;

    return map { s/([^a-zA-Z0-9_.!~*'()-])/uc sprintf("%%%02X", ord $1)/eg; $_ }
           map { Encode::encode_utf8($_) }
           @_
}

=head2 load_date Date

Loads a yyyy-mm-dd date into a L<DateTime> object.

=cut

sub load_date {
    my $self = shift;
    my $ymd  = shift;

    # XXX: this is a temporary hack until Hiveminder is pulled live
    $ymd =~ s/ 00:00:00$//;

    my ($y, $m, $d) = $ymd =~ /^(\d\d\d\d)-(\d\d)-(\d\d)$/
        or confess "Invalid date passed to load_date: $ymd. Expected yyyy-mm-dd.";

    return DateTime->new(
        time_zone => 'floating',
        year      => $y,
        month     => $m,
        day       => $d,
    );
}

=head2 email_eq Email, Email

Compares two email address. Returns true if they're equal, false if they're not.

=cut

sub email_eq {
    my $self = shift;
    my $a    = shift;
    my $b    = shift;

    # if one's defined and the other isn't, return 0
    return 0 unless (defined $a ? 1 : 0)
                 == (defined $b ? 1 : 0);

    return 1 if !defined($a) && !defined($b);

    # so, both are defined

    for ($a, $b) {
        s/<nobody>/<nobody\@localhost>/;
        my ($email) = Email::Address->parse($_);
        $_ = lc($email->address);
    }

    return $a eq $b;
}

=head2 is_me Email

Returns true if the given email looks like it is the current user's.

=cut

sub is_me {
    my $self = shift;
    my $email = shift;

    return 0 if !defined($email);

    return $self->email_eq($self->email, $email);
}

=head2 load_config

This will return a hash reference of the user's preferences. Because this
method is designed for use in small standalone scripts, it has a few
peculiarities.

=over 4

=item

It will C<warn> if the permissions are too liberal on the config file, and fix
them.

=item

It will prompt the user for an email and password if necessary. Given
the email and password, it will attempt to log in using them. If that fails,
then it will try again.

=item

Upon successful login, it will write a new config consisting of the options
already in the config plus session ID, email, and password.

=back

=cut

sub load_config {
    my $self = shift;

    $self->config_permissions;
    $self->read_config_file;

    # allow config to override everything. this may need to be less free in
    # the future
    while (my ($key, $value) = each %{ $self->config }) {
        $self->$key($value)
            if $self->can($key);
    }

    $self->prompt_login_info
        unless $self->config->{email} || $self->config->{sid};

    # update config if we are logging in manually
    unless ($self->config->{sid}) {

        # if we have user/pass in the config then we still need to log in here
        unless ($self->sid) {
            $self->login;
        }

        # now write the new config
        $self->config->{sid} = $self->sid;
        $self->write_config_file;
    }

    return $self->config;
}

=head2 config_permissions

This will warn about (and fix) config files being readable by group or others.

=cut

sub config_permissions {
    my $self = shift;
    my $file = $self->config_file;

    return if $^O eq 'MSWin32';
    return unless -e $file;
    my @stat = stat($file);
    my $mode = $stat[2];
    if ($mode & S_IRGRP || $mode & S_IROTH) {
        warn "Config file $file is readable by users other than you, fixing.";
        chmod 0600, $file;
    }
}

=head2 read_config_file

This transforms the config file to a hashref. It also does any postprocessing
needed, such as transforming localhost to 127.0.0.1 (due to an obscure bug,
probably in HTTP::Cookies)

=cut

sub read_config_file {
    my $self = shift;
    my $file = $self->config_file;

    return unless -e $file;

    $self->config(YAML::LoadFile($self->config_file) || {});

    if ($self->config->{site}) {
        # Somehow, localhost gets normalized to localhost.localdomain,
        # and messes up HTTP::Cookies when we try to set cookies on
        # localhost, since it doesn't send them to
        # localhost.localdomain.
        $self->config->{site} =~ s/localhost/127.0.0.1/;
    }
}

=head2 write_config_file

This will write the config to disk. This is usually only done when a sid is
discovered, but may happen any time.

=cut

sub write_config_file {
    my $self = shift;
    my $file = $self->config_file;

    YAML::DumpFile($file, $self->config);
    chmod 0600, $file;
}

=head2 prompt_login_info

This will ask the user for her email and password. It may do so repeatedly
until login is successful.

=cut

sub prompt_login_info {
    my $self = shift;

    print << "END_WELCOME";
Before we get started, please enter your @{[ $self->site ]}
username and password.

This information will be stored in @{[ $self->config_file ]}, 
should you ever need to change it.

END_WELCOME

    local $| = 1; # Flush buffers immediately

    while (1) {
        print "First, what's your email address? ";
        $self->config->{email} = <STDIN>;
        chomp($self->config->{email});

        require Term::ReadKey;
        print "And your password? ";
        Term::ReadKey::ReadMode('noecho');
        $self->config->{password} = <STDIN>;
        chomp($self->config->{password});
        Term::ReadKey::ReadMode('restore');

        print "\n";

        $self->email($self->config->{email});
        $self->password($self->config->{password});

        last if eval { $self->login };

        $self->email('');
        $self->password('');

        print "That combination doesn't seem to be correct. Try again?\n";
    }
}

=head1 SEE ALSO

L<Jifty>, L<Net::Hiveminder>

=head1 AUTHOR

Shawn M Moore, C<< <sartak at gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-net-jifty at rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Net-Jifty>.

=head1 COPYRIGHT & LICENSE

Copyright 2007 Best Practical Solutions.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;


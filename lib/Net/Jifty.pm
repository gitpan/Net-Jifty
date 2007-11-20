#!/usr/bin/env perl
package Net::Jifty;
use Moose;
use YAML;
use Encode;
use URI;
use LWP::UserAgent;

=head1 NAME

Net::Jifty - interface to online Jifty applications

=head1 VERSION

Version 0.01 released 20 Nov 07

=cut

our $VERSION = '0.01';

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
    is            => 'ro',
    isa           => 'Str',
    required      => 1,
    documentation => "The URL of your application",
);

has cookie_name => (
    is            => 'ro',
    isa           => 'Str',
    required      => 1,
    documentation => "The name of the session ID cookie. This can be found in your config under Framework/Web/SessinCookieName",
);

has appname => (
    is            => 'ro',
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

sub BUILD {
    my $self = shift;

    $self->login
        unless $self->sid;
}

=head2 login

This assumes your site is using L<Jifty::Plugin::Authentication::Password>.
If that's not the case, override this in your subclass.

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

    return join '/', map { $self->escape($_) } @_
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


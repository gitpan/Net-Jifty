use inc::Module::Install;

name            'Net-Jifty';
all_from        'lib/Net/Jifty.pm';

requires        'Moose';
requires        'LWP::UserAgent';
requires        'YAML';
requires        'URI';
requires        'Encode';

build_requires  'Test::More';
build_requires  'Test::MockObject';

auto_install;
WriteAll;



use strict;
use warnings;
use Test::More;

use lib '.';
use Kernel::Language::de_WorkordersToGroup;
use Kernel::Language::en_WorkordersToGroup;

my $German = bless { Translation => { 'Core sentinel' => 'deutsch' } }, 'Local::Language';
Kernel::Language::de_WorkordersToGroup::Data($German);
is( $German->{Translation}->{'Core sentinel'}, 'deutsch', 'German plugin translations preserve the existing OTOBO catalog' );
is( $German->{Translation}->{'Work Order'}, 'Arbeitsauftrag', 'German plugin translation is added' );

my $English = bless { Translation => { 'Core sentinel' => 'core' } }, 'Local::Language';
Kernel::Language::en_WorkordersToGroup::Data($English);
is( $English->{Translation}->{'Core sentinel'}, 'core', 'English plugin translations preserve the existing OTOBO catalog' );
is( $English->{Translation}->{'Instruction'}, 'Instruction', 'English plugin translation is added' );

done_testing();

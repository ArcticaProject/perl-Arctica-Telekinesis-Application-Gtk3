use strict;
use ExtUtils::MakeMaker;

WriteMakefile (
  AUTHOR        => 'Arctica Project Developers',
  ABSTRACT      => "Arctica Telekinesis Application (Gtk3)",
  NAME          => 'Arctica::Telekinesis::Application::Gtk3',
  (eval { ExtUtils::MakeMaker->VERSION(6.21) } ? (LICENSE => 'perl') : ()),
  PREREQ_PM     => {
    'Test::More' => '0.47',
  },
  VERSION_FROM  => 'lib/Arctica/Telekinesis/Application/Gtk3/Version.pm',
  clean               => { FILES => '' },
);

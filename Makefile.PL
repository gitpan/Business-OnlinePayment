use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'         => 'Business::OnlinePayment',
    'VERSION_FROM' => 'OnlinePayment.pm', # finds $VERSION
    'AUTHOR'       => 'Jason Kohles <email@jasonkohles.com>',
    'NORECURS'     => 1, # dont descend into subdirectories
    'PREREQ_PM'    => {'Net::SSLeay' => 0},
    #'dist'         => {CI => 'ci -l'},
);

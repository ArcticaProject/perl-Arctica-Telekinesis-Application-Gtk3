################################################################################
#          _____ _
#         |_   _| |_  ___
#           | | | ' \/ -_)
#           |_| |_||_\___|
#                   _   _             ____            _           _
#    / \   _ __ ___| |_(_) ___ __ _  |  _ \ _ __ ___ (_) ___  ___| |_
#   / _ \ | '__/ __| __| |/ __/ _` | | |_) | '__/ _ \| |/ _ \/ __| __|
#  / ___ \| | | (__| |_| | (_| (_| | |  __/| | | (_) | |  __/ (__| |_
# /_/   \_\_|  \___|\__|_|\___\__,_| |_|   |_|  \___// |\___|\___|\__|
#                                                  |__/
#          The Arctica Modular Remote Computing Framework
#
################################################################################
#
# Copyright (C) 2015-2016 The Arctica Project 
# http://arctica-project.org/
#
# This code is dual licensed: strictly GPL-2 or AGPL-3+
#
# GPL-2
# -----
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the
# Free Software Foundation, Inc.,
#
# 51 Franklin St, Fifth Floor, Boston, MA 02110-1301, USA.
#
# AGPL-3+
# -------
# This programm is free software; you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# This programm is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program; if not, write to the
# Free Software Foundation, Inc.,
# 51 Franklin St, Fifth Floor, Boston, MA 02110-1301, USA.
#
# Copyright (C) 2015-2016 Guangzhou Nianguan Electronics Technology Co.Ltd.
#                         <opensource@gznianguan.com>
# Copyright (C) 2015-2016 Mike Gabriel <mike.gabriel@das-netzwerkteam.de>
#
################################################################################
package Arctica::Telekinesis::Application::Gtk3;
use strict;
use Exporter qw(import);
use Data::Dumper;
use Arctica::Core::JABus::Socket;
use Arctica::Core::eventInit qw( genARandom BugOUT );
use Gtk3 -init;
use Glib::Object::Introspection;
Glib::Object::Introspection->setup(
	basename => "GdkX11",
	version => "3.0",
	package => "Gtk3::Gdk");
# Be very selective about what (if any) gets exported by default:
our @EXPORT = qw();
# And be mindfull of what we lett the caller request here too:
our @EXPORT_OK = qw();

my $arctica_core_object;
# Remote types: (NOTE TO $SELF)
# 1. ULTIMATE X (track nothing we're remotely X embedded!!)
# 2. FLOAT
# 	2.1. Float_embed (We're embedded in the remote session window but need to dodge other applications in the session)
# 	2.2. Float_free (Free floating natively in the client OS... need to also track session window states)
# 3. fullscreen (For platforms where fullscreen is the only way to get things done... So do we need to track anything?)
# 4. fallback_ss (serverside rendering X embedded loop back carrier window on the server side)
my $TEKIUNO = 0;


sub new {
	BugOUT(9,"TeKi AppGtk3 new->ENTER");
	if ($TEKIUNO eq 1) {die("Yeah... you probably don't want two of these in the same application!?!");} else {$TEKIUNO = 1;}
	my $class_name = $_[0];
	$arctica_core_object = $_[1];
	my $conf = $_[2];
	my $the_tmpdir = $arctica_core_object->{'a_dirs'}{'tmp_adir'};
	my $teki_tmpdir = "$the_tmpdir/teki";

	unless (-d $teki_tmpdir) {
		die("TeKi AppGtk3 unable to locate dir $teki_tmpdir ($!)");
	}
	
	my $self = {
		tmpdir => $teki_tmpdir,
		isArctica => 1, # Declare that this is a Arctica "something"
		aobject_name => "telekinesis_appcore",
	};
	bless($self, $class_name);

	if ($conf->{'services'}) {
		foreach my $key (keys $conf->{'services'}) {
			if ($key =~ /^([a-z]{4,24})$/) {
				my $service_name = $1;
				if ($conf->{'services'}{$service_name}) {
					$self->{'services'}{$service_name} = $conf->{'services'}{$service_name}
				}
			}
		}
	} else {
		die("TeKi AppGtk3 new: at least one service must be requested!");
	}


	$self->{'application_id'} = genARandom('id');
	$self->{'state'}{'active'} = 0;
	$self->{'teki_socket_id'} = $self->_get_tmp_local_socket_id;

	$self->{'teki_socket'} = Arctica::Core::JABus::Socket->new($arctica_core_object,{
		type	=>	"unix",
		destination =>	"local",
		is_client => 1,
		connect_to => $self->{'teki_socket_id'},
		handle_in_dispatch => {
				appinit => sub {$self->_app_init();},
#				appcom => \&my_Own_Sub1,
#				appreg => \&my_Own_Sub1,
#				tekictrl => \&my_Own_Sub1,
		},
		hooks => {
			on_ready => sub {$self->_appside_app_reg();},
		},
	});

	$arctica_core_object->{'aobj'}{'telekinesis_appcore'} = \$self;

	return $self;
	BugOUT(9,"TeKi AppGtk3 new->DONE");
}



sub _appside_app_reg {
	BugOUT(9,"TeKi AppGtk3 Registration->ENTER");
	my $self = $_[0];
	$self->{'teki_socket'}->client_send('appreg',{
		service_req => $self->{'services'},
	});
	BugOUT(9,"TeKi AppGtk3 Registration->DONE");
}

################################################################################
# GTK3 RELATED STUFF
sub _app_init {
	BugOUT(8,"Arctica::Telekinesis::Application::Gtk3 app_init->START");
	my $self = $_[0];
	my $init_data = {
		action => 'app_init',
	};
	if ($self->{'windows'}) {
#		print "GOT WINDERS!\n";
		foreach my $twid (keys $self->{'windows'}) {
#			print "W:\t$twid\n";

			$init_data->{'windows'}{$twid}{'state'} = $self->{'windows'}{$twid}{'state'};
#			$init_data->{'windows'}{$twid}{'targets'} = $self->{'windows'}{$twid}{'targets'};
		}
	}
	
	if ($self->{'targets'}) {
#		print "GOT TARGETS!\n";
		foreach my $ttid (keys $self->{'targets'}) {
#			print "T:\t$ttid\n";
			$init_data->{'targets'}{$ttid}{'state'} = $self->{'targets'}{$ttid}{'state'};
			$init_data->{'targets'}{$ttid}{'window'} = $self->{'targets'}{$ttid}{'window'};
			$init_data->{'targets'}{$ttid}{'service'} = $self->{'targets'}{$ttid}{'service'};
			if ($self->{'targets'}{$ttid}{'tmplnkid'}) {#TMP GARBAGE
				$init_data->{'targets'}{$ttid}{'tmplnkid'} = $self->{'targets'}{$ttid}{'tmplnkid'};#TMP GARBAGE
			}#TMP GARBAGE
#			$targets->{};
		}
	}
	
	#print "HOLLA YOLLA:\n\n",Dumper($tekiappco);
#	$self->{'teki_socket'}->client_send('appreg',{
#		service_req => "blablabla"
#	});
	$self->{'teki_socket'}->client_send('appctrl',$init_data);
	
	BugOUT(9,"Arctica::Telekinesis::Application::Gtk3 app_init->DONE");
}

sub _cinit_window {
	my $self = $_[0];
	my $twid = $_[1];
	$self->{'teki_socket'}->client_send('appcom',{
		action => 'init_w',
		wstate => $self->{'windows'}{$twid}{'state'},
	});
}

sub _cinit_target {
	my $self = $_[0];
	my $ttid = $_[1];
	$self->{'teki_socket'}->client_send('appcom',{
		action => 'init_t',
		tstate => $self->{'targets'}{$ttid}{'state'},
		tmplnkid => $self->{'targets'}{$ttid}{'tmplnkid'}#TMP GARBAGE
	});
}


sub check_n_send {
	my $self = $_[0];
	my %to_send;
	if ($self->{'_tmp'}) {
		print "SND\t",time,"\t:\n";
		print Dumper($self->{'_tmp'});
#		if ($self->{'tosock'}) {
		if (1 eq 1) {
			my $MODIFIED = 0;# FIX ME ! REMOVE THIS

			if ($self->{'_tmp'}{'w'}) {
				foreach my $id (keys $self->{'_tmp'}{'w'}) {
					print "\tID: $id\n";
					foreach my $val (keys $self->{'_tmp'}{'w'}{$id}) {
						print "\t\tVAL: $val\n";
						if ($self->{'_tmp'}{'w'}{$id}{$val} eq $self->{'_sent'}{'w'}{$id}{$val}) {
							delete $self->{'_tmp'}{'w'}{$id}{$val};

							print "\t\t>> REMOVED W $id $val\n";
							my $keycnt = keys $self->{'_tmp'}{'w'}{$id};
							print "\t\t\t>>>KEYS: $keycnt\n";
							if ($keycnt < 1) {
								delete $self->{'_tmp'}{'w'}{$id};
							}
						} else {
							$to_send{'w'}{$id}{$val} = $self->{'_tmp'}{'w'}{$id}{$val};
							$self->{'_sent'}{'w'}{$id}{$val} = $self->{'_tmp'}{'w'}{$id}{$val};
						}
					}
					
				}
				my $keycnt = keys $self->{'_tmp'}{'w'};
				print "\t\t\t>>>KEYS: $keycnt\n";
				if ($keycnt < 1) {
					delete $self->{'_tmp'}{'w'};
				} else {$MODIFIED = 1;}
			}
			if ($self->{'_tmp'}{'t'}) {
				foreach my $id (keys $self->{'_tmp'}{'t'}) {
					print "\tID: $id\n";
					if ($self->{'_tmp'}{'t'}{$id}{'w'} eq 1920) {
						warn("YAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAH GOT IT!!!");
					}
					foreach my $val (keys $self->{'_tmp'}{'t'}{$id}) {
						print "\t\tVAL: $val\n";
						if ($self->{'_tmp'}{'t'}{$id}{$val} eq $self->{'_sent'}{'t'}{$id}{$val}) {
							delete $self->{'_tmp'}{'t'}{$id}{$val};

							print "\t\t>> REMOVED T $id $val\n";
							my $keycnt = keys $self->{'_tmp'}{'t'}{$id};
							print "\t\t\t>>>KEYS: $keycnt\n";
							if ($keycnt < 1) {
								delete $self->{'_tmp'}{'t'}{$id};
							}
						} else {
							$to_send{'t'}{$id}{$val} = $self->{'_tmp'}{'t'}{$id}{$val};
							$self->{'_sent'}{'t'}{$id}{$val} = $self->{'_tmp'}{'t'}{$id}{$val};
						}
					}
					
				}
				my $keycnt = keys $self->{'_tmp'}{'t'};
				print "\t\t\t>>>KEYS: $keycnt\n";
				if ($keycnt < 1) {
					delete $self->{'_tmp'}{'t'};
				} else {$MODIFIED = 1;}
			}

			if ($self->{'_tmp'}{'force_send'} eq 1) {
				$self->{'_tmp'}{'force_send'} = 0;
#				%to_send = $self->{'_sent'};
				$MODIFIED = 1;
			}
			if ($MODIFIED eq 1) {
				warn "\tMODIFIED!\n";
				print Dumper($self->{'_tmp'});
				$self->{'teki_socket'}->client_send('appctrl',{
					action => 'state_change',
					data => \%to_send,
				});
			} else {
				print "\tNOT MODIFIED!\n";
			}
#			$self->{'tosock'}->($self->{'_tmp'});# FIX ME! ONLY DO THIS WHEN MODIFIED

		}
		$self->{'_tmp'} = undef;
	}
	my $cnt = keys %to_send;
#	print "KEY CNT:\t$cnt\n";
	if ($self->{'windows'}) {
#		print "GOT WINDERS!\n";
		foreach my $twid (keys $self->{'windows'}) {
#			print "W:\t$twid\n";
#			if ($self->{'windows'})
		}
	}
	if ($self->{'targets'}) {
#		print "GOT TARGETS!\n";
		foreach my $ttid (keys $self->{'targets'}) {
#			print "T:\t$ttid\n";
		}
	}
}

sub add_window {
	my $self = $_[0];
	my $new_window = $_[1];
	$new_window->set_title("TeKi TRACKED");
	my $new_id = genARandom('id');
	$self->{'windows'}{$new_id}{'thewindow'} = $new_window;
	$new_window->signal_connect(event => sub {$self->_handle_window_event($_[0],$_[1],$new_id);return 0;});
	#$new_window->signal_connect(destroy => sub { 	Gtk3->main_quit();});

	return $new_id;
}

sub rm_window {
	my $self = $_[0];
	my $rm_wid = $_[1];
	if ($self->{'windows'}{$rm_wid}) {
		delete($self->{'windows'}{$rm_wid}) or warn("Unable to untrack window [$rm_wid] ($!)");
	}
}

sub new_target {
	my $self = $_[0];
	my $wid = $_[1];
	my $target_service = lc($_[2]);# FIX ME! Do something smart to check if we requested a valid and supported service type.
	if ($self->{'windows'}{$wid}) {
		my $new_tid = genARandom('id');
		$self->{'windows'}{$wid}{'targets'}{$new_tid} = 1;
		$self->{'targets'}{$new_tid}{'window'} = $wid;
		$self->{'targets'}{$new_tid}{'widget'} = Gtk3::Socket->new;
		$self->{'targets'}{$new_tid}{'widget'}->signal_connect(realize => sub {print "REALIZED!!!",Dumper(@_),"XID:",
			$self->{'targets'}{$new_tid}{'widget'}->get_id,"\n";$self->{'targets'}{$new_tid}{'realized'} = 1;
			unless ($self->{'targets'}{$new_tid}{'state'}{'viz'} eq 0) {$self->{'targets'}{$new_tid}{'state'}{'viz'} = 1;}
			$self->_set_tmp('w',$wid,'geometry');
			$self->_handle_target_geometry_event($new_tid);

			return 0;});
		$self->{'targets'}{$new_tid}{'widget'}->signal_connect(unrealize => sub {print "UN-REALIZED WTF MAN!!!",Dumper(@_),"\n";$self->{'targets'}{$new_tid}{'realized'} = 0;return 0;});
		$self->{'targets'}{$new_tid}{'widget'}->signal_connect(visibility_notify_event => sub {$self->_handle_target_viz_event($new_tid,$_[1]);return 0;});
		$self->{'targets'}{$new_tid}{'widget'}->signal_connect(size_allocate => sub {$self->_handle_target_geometry_event($new_tid,@_);return 0;});
		$self->{'targets'}{$new_tid}{'service'} = $target_service;
#		$self->{'targets'}{$new_tid}{'widget'}->signal_connect(event => sub {$self->_handle_target_event($_[0],$_[1],$new_tid);return 0;});

#############################
# WHACKY BS LIFE SIGN
		my $bsls_timeout = Glib::Timeout->add(1000, sub {$self->{'_tmp'}{'force_send'} = 1;
#			$self->{'_tmp'}{'alive'}{} = 1;
			$self->{'_tmp'}{'t'}{$new_tid}{'alive'} = time;
#			$self->_set_tmp('t',$new_tid,'geometry');
			return 1;
		});
#############################

		return $new_tid;
	} else {
		die("You need to provide the TeKi WID of a predeclared application window");
	}
}

sub get_widget {
	my $self = $_[0];
	if ($self->{'targets'}{$_[1]}{'widget'}) {
		return $self->{'targets'}{$_[1]}{'widget'};
	} else {
		die("WTF!!");
	}
}

sub _set_tmp {
	my $self = $_[0];
	my $w_or_t = $_[1];
	my $id = $_[2];
	my $what = $_[3];
	my $value = $_[4];
	if ($w_or_t eq "w") {
#		print "SET TMP 'W'!!!\n";
		if ($self->{'windows'}{$id}{'thewindow'}) {
			if ($what eq 'geometry') {
#				print "GEOMETRY!!!\n";
				my ($os_x,$os_y) = $self->{'windows'}{$id}{'thewindow'}->get_position;
				my ($of_x,$of_y,$width,$height) = $self->{'windows'}{$id}{'thewindow'}->get_window->get_geometry;
#				os = on screen position
#				of = offset (accounting for window decoration stuffs).
				# Experimental if this is all we need to transmit remove the os+of stuff
				$self->{'_tmp'}{'w'}{$id}{'x'} = ($os_x + $of_x);
				$self->{'_tmp'}{'w'}{$id}{'y'} = ($os_y + $of_y);
				
				# First stick the values into "_tmp"
#				$self->{'_tmp'}{'w'}{$id}{'os_x'} = $os_x;
#				$self->{'_tmp'}{'w'}{$id}{'os_y'} = $os_y;
#				$self->{'_tmp'}{'w'}{$id}{'of_x'} = $of_x;
#				$self->{'_tmp'}{'w'}{$id}{'of_y'} = $of_y;
								
				# Then put them somewhere more "permanent" (mostly for debug etc...)
				$self->{'windows'}{$id}{'state'}{'os_x'} = $os_x;
				$self->{'windows'}{$id}{'state'}{'os_y'} = $os_y;
				$self->{'windows'}{$id}{'state'}{'of_x'} = $of_x;
				$self->{'windows'}{$id}{'state'}{'of_y'} = $of_y;
				# Do we even care about the window W&H? 
#				$self->{'windows'}{$id}{'state'}{'width'} = $width;
#				$self->{'windows'}{$id}{'state'}{'height'} = $height;
			} elsif ($what eq 'map') {
				$self->{'windows'}{$id}{'state'}{'map'} = $value;
				$self->{'_tmp'}{'w'}{$id}{'map'} = $value;
			} elsif ($what eq 'maximized') {
				warn("MAXIMIZE STATE: $value");
#				$self->{'windows'}{$id}{'state'}{'max'} = $value;
#				$self->{'_tmp'}{'w'}{$id}{'max'} = $value;
				foreach my $ftid (keys $self->{'windows'}{$id}{'targets'}) {
					warn("$id/$ftid");
					$self->_set_tmp('w',$id,'geometry');
				#	$self->_set_tmp('t',$ftid,'geometry');
				}

			} elsif ($what eq 'focused') {
				$self->{'windows'}{$id}{'state'}{'focus'} = $value;
				$self->{'_tmp'}{'w'}{$id}{'focus'} = $value;
			}
		}
	} elsif ($w_or_t eq "t") {
		if ($self->{'targets'}{$id}{'widget'}) {
			if ($what eq 'viz') {
				$self->{'targets'}{$id}{'state'}{'viz'} = $value;
				$self->{'_tmp'}{'t'}{$id}{'viz'} = $value;
			} elsif ($what eq 'geometry') {
				my $talloc = $self->{'targets'}{$id}{'widget'}->get_allocation;
				my ($aX,$aY) = $self->_get_absolute_target_pos($self->{'targets'}{$id}{'widget'});
				BugOUT(8,"POS: $aX,$aY $talloc->{'width'} $talloc->{'height'}");
				$self->{'_tmp'}{'t'}{$id}{'x'} = $aX;
				$self->{'_tmp'}{'t'}{$id}{'y'} = $aY;
				$self->{'_tmp'}{'t'}{$id}{'w'} = $talloc->{'width'};
				$self->{'_tmp'}{'t'}{$id}{'h'} =  $talloc->{'height'};

				$self->{'targets'}{$id}{'state'}{'x'} = $aX;
				$self->{'targets'}{$id}{'state'}{'y'} = $aY;
				$self->{'targets'}{$id}{'state'}{'w'} = $talloc->{'width'};
				$self->{'targets'}{$id}{'state'}{'h'} = $talloc->{'height'};
			}
		}
	} else {
		die("Someone screwed up pretty f-ing bad... somewhere!!!");
	}
}


sub _handle_window_event {
#	Stuff that happen here should never be logged other than when explicitly doing dev work.
	my ($self,$the_window, $event,$wid) = @_;
#	print "TeKiPM MAINWIN\tE:\t$the_window\t",$event->type,"[TeKiEID:\t$new_id]\n";

	if ($event->type eq "configure") {#Size or position change detection.
		$self->_set_tmp('w',$wid,'geometry');

	} elsif ($event->type eq "visibility-notify") {
		# WE DON'T CARE....  TRACKING THIS INDIVIDUALY FOR EACH TARGET!
#		print "\t\t[",$event->state,"]\n";# Change this line to use BugOUT but leave it commented out..... !!!!

	} elsif ($event->type eq "map") {
		$self->_set_tmp('w',$wid,'map',1);
		$self->_set_tmp('w',$wid,'geometry');
#		($self->{'windows'}{$new_id}{'state'}{'x'},$self->{'windows'}{$new_id}{'state'}{'y'}) = $the_window->get_position;
#		 = $self->{'windows'}{$new_id}{'state'}{'x'};
#		$self->{'_tmp'}{'w'}{$new_id}{'y'} = $self->{'windows'}{$new_id}{'state'}{'y'};

	} elsif ($event->type eq "unmap") {
		$self->_set_tmp('w',$wid,'map',0);

	} elsif ($event->type eq "window-state") { 

		if ($event->new_window_state =~ /tiled/) {
			warn("YAY WE ARE TILED YOHO!!!!");
		}

		if (($event->new_window_state =~ /maximized/) or ($event->new_window_state =~ /tiled/)) {
			$self->_set_tmp('w',$wid,'maximized',1);
			BugOUT(8,"Maximized!");
		} else {
			$self->_set_tmp('w',$wid,'maximized',0);
			BugOUT(8,"Unmaximized!");
		}

		if ($event->new_window_state =~ /focused/) {
			$self->_set_tmp('w',$wid,'focused',1);
		} else {
			$self->_set_tmp('w',$wid,'focused',0);
		}

		$self->_set_tmp('w',$wid,'geometry');
		foreach my $tid (keys $self->{'windows'}{$wid}{'targets'}) {
			my $talloc = $self->{'targets'}{$tid}{'widget'}->get_allocation;
			print "\n\n\nTID:>>>>>>>>>>>>>>>>>>>>>>>>>>>>>: $tid\n$talloc->{'width'}:T\n\n";
			$self->{'_tmp'}{'t'}{$tid}{'w'} = $talloc->{'width'};
			$self->{'_tmp'}{'t'}{$tid}{'h'} =  $talloc->{'height'};
			$self->_set_tmp('t',$tid,'geometry');
		}
#		$self->_set_tmp('w',$wid,'wstate',"$maximized,$focused");

	} elsif ($event->type eq "delete") {
		$self->_set_tmp('w',$wid,'map',0);
		$self->rm_window($wid);
		warn("You may now have orphans!?!");# FIX ME: ADD SOME "IF GOT TARGER BLABALBA" HERE...
		Glib::Timeout->add(1000, sub {exit;});
	}

#	print "\n";
	return 0;
}

sub _handle_target_viz_event {
	my $self = $_[0];
	my $tid = $_[1];
	my $event = $_[2];

	if ($event->state eq "unobscured") {
		$self->_set_tmp('t',$tid,'viz',1);
		$self->_handle_target_geometry_event($tid);
	} else {
		$self->_set_tmp('t',$tid,'viz',0);
	}
	return 0;
}

sub _handle_target_geometry_event {
	my $self = $_[0];
	my $tid = $_[1];
	
	if (($self->{'targets'}{$tid}{'state'}{'viz'} ne 2) and ($self->{'targets'}{$tid}{'realized'} eq 1)) {
		$self->_set_tmp('t',$tid,'geometry');
	}

	return 0;
}

sub _get_absolute_target_pos {
	my $chkwin = $_[1];
	my $absolute_x = 0;
	my $absolute_y = 0;

	while ($chkwin->get_window->get_window_type !~ /^toplevel|popup$/) {
		my ($pwin_x, $pwin_y) = $chkwin->get_window->get_position;
		$absolute_x += $pwin_x;
		$absolute_y += $pwin_y;
		$chkwin = $chkwin->get_parent or die("WTF We should have stopped by now...");
	}

	return ($absolute_x,$absolute_y);
}


################################################################################
# FIX ME! TMP STUFF, REMOVE IN FINAL VERSION!
sub _get_tmp_local_socket_id {
	my $self = $_[0];
	if (-f "$self->{'tmpdir'}/server_sockets.info") {
		open(SIF,"$self->{'tmpdir'}/server_sockets.info");
		my ($local_line,undef) = <SIF>;
		close(SIF);
		print "LL1:\t$local_line\n";
		$local_line =~ s/[\n\s]//g;
		print "LL2:\t$local_line\n";
		if ($local_line =~ /^local\:([0-9a-zA-Z]*)$/) {
			my $sock_id = $1;
			return $sock_id;
		} else {
			die("TOTAL FAILURE! BUHUHUHHUUUUUUUUUUU!");
		}
	} else {
		die("TOTAL FAILURE! BUHUHUHHUUUUUUUUUUU!");
	}
}

1;

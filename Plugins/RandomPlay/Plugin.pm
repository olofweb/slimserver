package Plugins::RandomPlay::Plugin;

# $Id$
#
# Originally written by Kevin Deane-Freeman (slim-mail (A_t) deane-freeman.com).
#
# New world order by Dan Sully - <dan | at | slimdevices.com>
# Further hacks by Max Spicer

# This code is derived from code with the following copyright message:
#
# SlimServer Copyright (C) 2005 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Slim::Buttons::Home;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

my %functions    = ();
my %stopcommands = ();
# Random play type for each client
my %type         = ();
# Display text for each mix type
my %displayText  = ();
# Type selected using INPUT.List
my %userType     = ();
my $htmlTemplate = 'plugins/RandomPlay/randomplay_list.html';

sub getDisplayName {
	return 'PLUGIN_RANDOM';
}

# Add random tracks to playlist if necessary
sub playRandom {
	# If addOnly, then track(s) are appended to end.  Otherwise, a new playlist is created.
	my ($client, $type, $addOnly) = @_;

	# disable this during the course of this function, since we don't want
	# to retrigger on commands we send from here.
	Slim::Control::Command::clearExecuteCallback(\&commandCallback);

	$type ||= 'track';
	$type   = lc($type);
	
	if ($type ne 'disable' && $type ne $type{$client}) {
		$::d_plugins && msg("RandomPlay: doing showBriefly\n");
		$client->showBriefly(string($addOnly ? 'ADDING_TO_PLAYLIST' : 'NOW_PLAYING'),
							 string(sprintf('PLUGIN_RANDOM_%s', uc($type))));
	}

	my $songIndex = Slim::Player::Source::streamingSongIndex($client);
	my $songsRemaining = Slim::Player::Playlist::count($client) - $songIndex - 1;
    $::d_plugins && msg("RandomPlay: $songsRemaining songs remaining, songIndex = $songIndex\n");

	# Work out how many items need adding
	my $numItems = 0;
	if ($type eq 'track') {
		# Add new tracks if there aren't enough after the current track
		my $numRandomTracks = Slim::Utils::Prefs::get('plugin_random_number_of_tracks');
		if (! $addOnly) {
			$numItems = $numRandomTracks;
		} elsif ($songsRemaining < $numRandomTracks - 1) {
			$numItems = $numRandomTracks - 1 - $songsRemaining;
		} else {
			$::d_plugins && msgf("RandomPlay: $songsRemaining items remaining so not adding new track\n");
		}

	} elsif ($type ne 'disable' && ($type ne $type{$client} || $songsRemaining <= 0)) {
		# Old artist/album is finished or new random mix started.  Add a new one
		# Find two artists/albums just in case the first one only results in one track
		$numItems = 2;
	}

	if ($numItems) {
		unless ($addOnly) {
			Slim::Control::Command::execute($client, [qw(stop)]);
			Slim::Control::Command::execute($client, [qw(power 1)]);
		}
		
		my $ds    = Slim::Music::Info::getCurrentDataStore();
		my $find  = {};
	
		$::d_plugins && msg("RandomPlay: Starting random selection of $numItems items for type: [$type]\n");
	
		if ($type eq 'track') {
			# Find only tracks, not albums etc
			$find->{'audio'} = 1;
		}
	
		my $items = $ds->find({
			'field'  => $type,
			'find'   => $find,
			'sortBy' => 'random',
			'limit'  => $numItems,
			'cache'  => 0,
		});
		
		# Pull the first track off to add / play it if needed.
		my $item = shift @{$items};
	
		if ($item && ref($item)) {
			my $string = $type eq 'artist' ? $item->name : $item->title;
			$::d_plugins && msgf("RandomPlay: %s %s: %s, %d\n",
								 $addOnly ? 'Adding' : 'Playing',
								 $type, $string, $item->id);
	
			Slim::Player::Playlist::shuffle($client, 0);
	
			# Replace the current playlist with the first item / track or add it to end
			$client->execute(['playlist', $addOnly ? 'addtracks' : 'loadtracks', sprintf('%s=%d', $type, $item->id)]);
			
			# Add the remaining items to the end
			if ($type eq 'track') {
				if ($numItems > 1) {
					$::d_plugins && msg("Adding %i tracks to end of playlist", scalar @$items);
					$client->execute(['playlist', 'addtracks', 'listRef', $items]);
				}
			} elsif (Slim::Player::Playlist::count($client) == 1) {
				# First artist/album only had one track so add another one.  Otherwise, plugin
				# would never add any more tracks
				$item = shift @$items;
				if ($item && ref($item)) {
					$string = $type eq 'artist' ? $item->name : $item->title;
					$::d_plugins && msgf("RandomPlay: Adding %s: %s, %d\n", $type, $string, $item->id);
				
					$client->execute(['playlist', 'addtracks', sprintf('%s=%d', $type, $item->id)]);
				}
			}
	
			# Set the Now Playing title.
			$client->currentPlaylist($client->string('PLUGIN_RANDOM_'.uc($type)));
	
			# Never show random as modified, since its a living playlist
			$client->currentPlaylistModified(0);	
		}
	} elsif ($type eq 'disable') {
		# Disable random play
				
		Slim::Control::Command::clearExecuteCallback(\&commandCallback);
		$::d_plugins && msg("RandomPlay: cyclic mode ended\n");
		$client->showBriefly(string('PLUGIN_RANDOM'), string('PLUGIN_RANDOM_DISABLED'));				
	}
	
	if ($type eq 'disable') {
		$type{$client} = undef;
	} else {
		$::d_plugins && msgf("RandomPlay: Playing continuous %s mode with %i items\n",
							 $type,
							 Slim::Player::Playlist::count($client));
		Slim::Control::Command::setExecuteCallback(\&commandCallback);
		
		# Do this last to prevent menu items changing too soon
		$type{$client} = $type;
		# Make sure that changes in menu items are displayed
		$client->update();
	}
}

# Returns the display text for the INPUT.List item for a mix type
sub getDisplayText {
	my ($client, $listItem) = @_;
	
	if (! %displayText) {
		%displayText = (
			track  => 'PLUGIN_RANDOM_TRACK',
			album  => 'PLUGIN_RANDOM_ALBUM',
			artist => 'PLUGIN_RANDOM_ARTIST'
		)
	}	
	
	if ($listItem eq $type{$client}) {
		return $displayText{$listItem} . '_STOP';
	} else {
		return $displayText{$listItem};
	}
}

sub setMode {
	my $client = shift;
	my $method = shift;
	
	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	# use INPUT.List to display the list of feeds
	my %params = (
		header          => 'PLUGIN_RANDOM_PRESS_PLAY',
		stringHeader    => 1,
		listRef         => [qw(track album artist)],
		overlayRef      => sub { return (undef, shift->symbols('notesymbol')) },
		externRef       => \&getDisplayText,
		stringExternRef => 1,
		valueRef        => \$userType{$client},
	);

	Slim::Buttons::Common::pushModeLeft($client, 'INPUT.List', \%params);
}

sub commandCallback {
	my ($client, $paramsRef) = @_;

	my $slimCommand = $paramsRef->[0];

	# we dont care about generic ir blasts
	return if $slimCommand eq 'ir';

	$::d_plugins && msgf("RandomPlay: received command %s\n", join(' ', @$paramsRef));

	if (!defined $client || !defined $type{$client}) {

		$::d_plugins && msg("RandomPlay: No client!\n");
		bt();
		return;
	}
	
	$::d_plugins && msgf("RandomPlay: while in mode: %s, from %s\n",
						 $type{$client}, $client->name);

	my $songIndex = Slim::Player::Source::streamingSongIndex($client);

	if ($slimCommand eq 'newsong'
		|| $slimCommand eq 'playlist' && $paramsRef->[1] eq 'delete' && $paramsRef->[2] > $songIndex) {

        if ($::d_plugins) {
			if ($slimCommand eq 'newsong') {
				msg("RandomPlay: new song detected ($songIndex)\n");
			} else {
				msg("RandomPlay: deletion detected ($paramsRef->[2]");
			}
		}
		
		if ($songIndex && Slim::Utils::Prefs::get('plugin_random_remove_old_tracks')) {
			$::d_plugins && msg("RandomPlay: Stripping off completed track(s)\n");

			Slim::Control::Command::clearExecuteCallback(\&commandCallback);
			# Delete tracks before this one on the playlist
			for (my $i = 0; $i < $songIndex; $i++) {
				Slim::Control::Command::execute($client, ['playlist', 'delete', 0]);
			}
			Slim::Control::Command::setExecuteCallback(\&commandCallback);
		}

		playRandom($client, $type{$client}, 1);
	} elsif (($slimCommand eq 'playlist') && exists $stopcommands{$paramsRef->[1]}) {

		$::d_plugins && msgf("RandomPlay: cyclic mode ending due to playlist: %s command\n", join(' ', @$paramsRef));
		playRandom($client, 'disable');
	}
}

sub initPlugin {
	%functions = (
		'play' => sub {
			my $client = shift;
			my $newType = ${$client->param('valueRef')};
			
			# If mode is already enabled, disable it
			if ($newType eq $type{$client}) {
				$newType = 'disable';
			}
			playRandom($client, $newType, 0);
		},
		
		'add' => sub {
			my $client = shift;
			my $newType = ${$client->param('valueRef')};
			
			# If mode is already enabled, disable it
			if ($newType eq $type{$client}) {
				$newType = 'disable';
			}
			playRandom($client, $newType, 1);
		},

		'tracks' => sub {
			my $client = shift;

			playRandom($client, 'track');
		},

		'albums' => sub {
			my $client = shift;

			playRandom($client, 'album');
		},

		'artists' => sub {
			my $client = shift;

			playRandom($client, 'artist');
		},
	);

	# playlist commands that will stop random play
	%stopcommands = (
		'clear' => 1,
		'loadtracks' => 1, # multiple play
		'playtracks' => 1, # single play
	);
}

sub shutdownPlugin {
	Slim::Control::Command::clearExecuteCallback(\&commandCallback);
}

sub getFunctions {
	return \%functions;
}

sub webPages {

	my %pages = (
		"randomplay_list\.(?:htm|xml)" => \&handleWebList,
		"randomplay_mix\.(?:htm|xml)"  => \&handleWebMix,
	);

	my $value = $htmlTemplate;

	if (grep { /^RandomPlay::Plugin$/ } Slim::Utils::Prefs::getArray('disabledplugins')) {

		$value = undef;
	}

	Slim::Web::Pages::addLinks("browse", { 'PLUGIN_RANDOM' => $value });

	return \%pages;
}

sub handleWebList {
	my ($client, $params) = @_;

	return Slim::Web::HTTP::filltemplatefile($htmlTemplate, $params);
}

sub handleWebMix {
	my ($client, $params) = @_;

	if ($params->{'type'}) {
		playRandom($client, $params->{'type'}, $params->{'addOnly'});
	}

	return Slim::Web::HTTP::filltemplatefile($htmlTemplate, $params);
}

sub setupGroup {

	my %setupGroup = (

		PrefOrder => [qw(plugin_random_number_of_tracks plugin_random_remove_old_tracks)],
		GroupHead => string('PLUGIN_RANDOM'),
		GroupDesc => string('SETUP_PLUGIN_RANDOM_DESC'),
		GroupLine => 1,
		GroupSub  => 1,
		Suppress_PrefSub  => 1,
		Suppress_PrefLine => 1,
	);

	my %setupPrefs = (

		'plugin_random_number_of_tracks' => {

			'validate'     => \&Slim::Web::Setup::validateInt,
			'validateArgs' => [1, undef, 1],
		},

		'plugin_random_remove_old_tracks' => {
			'validate' => \&Slim::Web::Setup::validateTrueFalse,
			'options' => {
				'1' => string('SETUP_PLUGIN_RANDOM_REMOVE_OLD_TRACKS'),
				'0' => string('SETUP_PLUGIN_RANDOM_DONT_REMOVE_OLD_TRACKS')
			}
		}
	);

	checkDefaults();

	return (\%setupGroup,\%setupPrefs);
}

sub checkDefaults {

	if (!Slim::Utils::Prefs::isDefined('plugin_random_number_of_tracks')) {
		Slim::Utils::Prefs::set('plugin_random_number_of_tracks', 10)
	}
	if (!Slim::Utils::Prefs::isDefined('plugin_random_remove_old_tracks')) {
		Slim::Utils::Prefs::set('plugin_random_remove_old_tracks', 0)
	}
}

sub strings {
	return <<EOF;
PLUGIN_RANDOM
	DE	Zufälliger Mix
	EN	Random Mix

PLUGIN_RANDOM_DISABLED
	EN	Random Mix Stopped

PLUGIN_RANDOM_TRACK
	DE	Zufälliger Lieder Mix
	EN	Random Songs Mix

PLUGIN_RANDOM_TRACK_STOP
	EN	Stop Random Songs Mix

PLUGIN_RANDOM_ALBUM
	DE	Zufälliger Album Mix
	EN	Random Album Mix

PLUGIN_RANDOM_ALBUM_STOP
	EN	Stop Random Album Mix

PLUGIN_RANDOM_ARTIST
	DE	Zufälliger Interpreten Mix
	EN	Random Artist Mix

PLUGIN_RANDOM_ARTIST_STOP
	EN	Stop Random Artist Mix

PLUGIN_RANDOM_PRESS_PLAY
	DE	Zufälliger Mix
	EN	Random Mix (Press PLAY or ADD to select)

PLUGIN_RANDOM_CHOOSE_DESC
	DE	Wählen Sie eine Zufallsmix-Methode:
	EN	Choose a random mix below:

PLUGIN_RANDOM_SONG_DESC
	DE	Zufällige Lieder aus Ihrer Sammlung
	EN	Random songs from your whole library.

PLUGIN_RANDOM_ARTIST_DESC
	DE	Zufälliger Interpret aus Ihrer Sammlung
	EN	Random artists from your whole library.

PLUGIN_RANDOM_ALBUM_DESC
	DE	Zufälliges Album aus Ihrer Sammlung
	EN	Random albums from your whole library.

SETUP_PLUGIN_RANDOM_DESC
	DE	Sie können zufällig Musik aus Ihrer Sammlung zusammenstellen lassen. Geben Sie hier an, wieviele Lieder jeweils zufällig der Wiedergabeliste hinzugefügt werden sollen.
	EN	Random Mix lets SlimServer create a random selections of songs from your entire library. When creating a random mix of songs, you can specify how many upcoming songs SlimServer should display.

SETUP_PLUGIN_RANDOM_NUMBER_OF_TRACKS
	DE	Anzahl Lieder für Zufallsmix
	EN	Number of upcoming songs in a random mix

SETUP_PLUGIN_RANDOM_REMOVE_OLD_TRACKS_DESC
	DE	Lieder, die zufällig abgespielt wurden, können nach der Wiedergabe aus der Liste entfernt oder darin belassen werden.
	EN	Songs that are played using Random Mix can be removed after they are played or remain on the playlist.

SETUP_PLUGIN_RANDOM_REMOVE_OLD_TRACKS
	DE	Entferne Lieder
	EN	Remove Played Songs

SETUP_PLUGIN_RANDOM_DONT_REMOVE_OLD_TRACKS
	DE	Lieder in Liste lassen
	EN	Don't Remove Played Songs



EOF

}

1;

__END__

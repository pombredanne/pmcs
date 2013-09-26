#!/usr/bin/env perl

require HTTP::Request;

use Cwd;
use File::Basename;
use File::Copy;
use File::Path;
use File::Spec::Functions;
use File::Temp qw/ tempfile tempdir /;
use LWP::UserAgent;
use Sys::Hostname;

# Variable declarations
my $PORT;
my $FQDN;
my $DOMAIN;
my $CLASS;
my $REPO;
my $REPOTYPE;
my $PLATFORM;
my $KEYWORDS;
my $RESULTREPO;
my $SCAPSCANOVAL;
my $SCAPSCANOVAL_NOID;
my $SCAPSCANXCCDF;
my $SCAPSCANXCCDF_NOPROFILE;

my($day, $month, $year) = (localtime)[3,4,5];
my $LOCALDATE=sprintf("%.4d%.2d%.2d", $year+1900, $month+1, $day);

my $CDIR=cwd();

my $TMPDIR=tempdir( CLEANUP => 1);

# Functions
sub nice_die {
  my $RC = shift;
  print("!! ", @_, "\n");
  exit($RC);
}

sub sendResults {
  my $FILE = shift;
  my $FILENAME = shift;
  my $REPOTYPE;
  my $POSTRES;

  if ($RESULTREPO =~ /^([^:]*):.*/i) {
    $REPOTYPE = $1;
  };

  if (!defined($FILENAME)) {
    $POSTRES = "${RESULTREPO}";
    $POSTRES =~ s/\@\@TARGETNAME\@\@/${FQDN}/g;
    $POSTRES =~ s/\@\@FILENAME\@\@/${FILE}/g;
    $POSTRES =~ s/\@\@DATE\@\@/${LOCALDATE}/g;
  } else {
    $POSTRES = "${RESULTREPO}";
    $POSTRES =~ s/\@\@TARGETNAME\@\@/${FQDN}/g;
    $POSTRES =~ s/\@\@FILENAME\@\@/${FILENAME}/g;
    $POSTRES =~ s/\@\@DATE\@\@/${LOCALDATE}/g;
  };

  copyResourceToRemote("${FILE}", "${POSTRES}");
};

sub evaluateStreams {
  foreach $STREAM (local_file_cat(catfile("${TMPDIR}", "list"))) {
    my $STREAMTYPE;
    my $STREAMRESULTID;
    my $STREAMPATH;
    my $STREAMID;
    my $STREAMNAME;
    my $COMMAND;

    if ($STREAM =~ /^([^#]*)#([^#]*)#([^#]*)#(.*)/i) {
      $STREAMTYPE = $1;
      $STREAMRESULTID = $2;
      $STREAMPATH = $3;
      $STREAMID = $4;
    };

    print("-- Evaluating STREAM ${STREAMPATH} (type ${STREAMTYPE}, id ${STREAMID})\n");
    print("\n");
    $STREAMNAME = basename(${STREAMPATH});
    if (copyResourceToLocal("${REPO}/stream/${STREAMPATH}", catfile("${TMPDIR}", "${STREAMNAME}")) == 0) {
      if ($STREAMTYPE eq "xccdf") {
        if ((!defined($STREAMID)) || ($STREAMID eq "")) {
	  $COMMAND = "${SCAPSCANXCCDF_NOPROFILE}";
	  $COMMAND =~ s/\@\@STREAMNAME\@\@/${STREAMNAME}/g;
	  $COMMAND =~ s/\@\@XCCDFRESULTNAME\@\@/${STREAMRESULTID}-xccdf-results.xml/g;
	  $COMMAND =~ s/\@\@OVALRESULTNAME\@\@/${STREAMRESULTID}-oval-results.xml/g;
	} else {
	  $COMMAND = "${SCAPSCANXCCDF}";
	  $COMMAND =~ s/\@\@STREAMNAME\@\@/${STREAMNAME}/g;
	  $COMMAND =~ s/\@\@XCCDFRESULTNAME\@\@/${STREAMRESULTID}-xccdf-results.xml/g;
	  $COMMAND =~ s/\@\@OVALRESULTNAME\@\@/${STREAMRESULTID}-oval-results.xml/g;
	  $COMMAND =~ s/\@\@STREAMID\@\@/${STREAMID}/g;
	};
	print("Running ${COMMAND}\n");
	chdir(${TMPDIR});
	system(${COMMAND});
	sendResults("${STREAMRESULTID}-xccdf-results.xml");
	# Hack because oscap does not allow providing filename for oval results
	my @OVALFILES = glob ("*.xml.result.xml");
	foreach $OVALFILE (@OVALFILES) {
	  if (!($OVALFILE =~ /\%/i)) {
	    $OVALFILE = basename($OVALFILE);
            sendResults ("${OVALFILE}", "${STREAMRESULTID}-oval-results.xml.${OVALFILE}");
	  };
	};
	if ( -f "${STREAMRESULTID}-oval-results.xml" ) {
          sendResults ("${STREAMRESULTID}-oval-results.xml");
	};
      } elsif ($STREAMTYPE eq "oval") {
        if ((!defined($STREAMID)) || ($STREAMID eq "")) {
	  $COMMAND = "${SCAPSCANOVAL_NOID}";
	  $COMMAND =~ s/\@\@STREAMNAME\@\@/${STREAMNAME}/g;
	  $COMMAND =~ s/\@\@OVALRESULTNAME\@\@/${STREAMRESULTID}-oval-results.xml/g;
	} else {
	  $COMMAND = "${SCAPSCANOVAL}";
	  $COMMAND =~ s/\@\@STREAMNAME\@\@/${STREAMNAME}/g;
	  $COMMAND =~ s/\@\@OVALRESULTNAME\@\@/${STREAMRESULTID}-oval-results.xml/g;
	  $COMMAND =~ s/\@\@STREAMID\@\@/${STREAMID}/g;
	};
	print("Running ${COMMAND}\n");
	chdir(${TMPDIR});
	system(${COMMAND});
	sendResults("${STREAMRESULTID}-oval-results.xml");
      };
    } else {
      nice_die(1, "Could not copy ${REPO}/stream/${STREAMPATH} to " . catfile("${TMPDIR}", "${STREAMNAME}") . "\n"); 
    };
  };
};

sub file_contains {
  my $EXPR = shift;
  my $FILENAME = shift;

  open my $FILEHANDLE, $FILENAME or die "Could not open $FILENAME: $!";

  my @lines = sort grep /$EXPR/, <$FILEHANDLE>;
  my $size = scalar @lines;
  return($size);
};

sub file_show_value {
  my $EXPR = shift;
  my $FILENAME = shift;

  open my $FILEHANDLE, $FILENAME or die "Could not open $FILENAME: $!";

  my @lines = sort grep /^$EXPR=/, <$FILEHANDLE>;
  foreach $line (@lines) {
    if ($line =~ /^[^=]*=(.*)/i) {
      my $value = $1;
      return($value);
    };
  };
};

sub file_show_value_cleaned {
  my $EXPR = shift;
  my $FILENAME = shift;

  open my $FILEHANDLE, $FILENAME or die "Could not open $FILENAME: $!";

  my @lines = sort grep /^$EXPR=/, <$FILEHANDLE>;
  foreach $line (@lines) {
    if ($line =~ /^[^=]*=(.*)/i) {
      my $value = $1;
      $value =~ s/[^[:alnum:]]/_/g;
      return($value);
    };
  };
};

sub local_wget {
  my $URI = shift;
  my $DST = shift;

  $user_agent = new LWP::UserAgent;

  $request    = HTTP::Request->new(GET => $URI);
  $response   = $user_agent->request($request);

  open FILEHANDLE, ">$DST";
  print FILEHANDLE $response->{_content};

  close FILEHANDLE
}

sub local_wpost {
  my $SRC = shift;
  my $DST = shift;

  $user_agent = new LWP::UserAgent;

  $request    = HTTP::Request->new(POST => $DST, [filecontent => $SRC]);
  $response   = $user_agent->request($request);
}

sub copyResourceToLocal {
  my $SRC = shift;
  my $DST = shift;
  my $RC  = 0;

  my $PROTO = "";


  if ($SRC =~ /^([^:]*):.*/i) { $PROTO = $1 };
  if ($PROTO eq "file") {
    my $LOCALSRC;
    if ($SRC =~ /^[^:]*:\/\/(.*)/i) { 
    	$LOCALSRC = $1;
    	if ($CLASS eq "windows") {
    		$LOCALSRC =~ s/\//\\/g;
    	};
    };
    if (-e $LOCALSRC) {
      copy($LOCALSRC, $DST);
      if (! -e $DST) {
        $RC=1;
      }
    } else {
      $RC=1;
    };
  } elsif (($PROTO eq "http") || ($PROTO eq "https")) {
    local_wget($SRC, $DST);
    if (! -e $DST) {
      $RC=1;
    }
  };

  return($RC);
}

sub local_file_append {
  my $ROSRC = shift;
  my $DST   = shift;

  open FILEHANDLE, ">>${DST}" or die "Could not append to $DST: $!";
  open READHANDLE, "<${ROSRC}" or die "Could not open $ROSRC: $!";
  while (my $line = <READHANDLE>) { print FILEHANDLE $line; };
  close FILEHANDLE;
  close READHANDLE;
};

sub local_file_cat {
  my $SRC = shift;
  my @lines;

  open FILEHANDLE, "<${SRC}" or die "Could not open ${SRC}: $!";
  @lines = <FILEHANDLE>;
  close(FILEHANDLE);

  return(@lines);
}

sub copyResourceToRemote {
  my $SRC = shift;
  my $DST = shift;
  my $RC  = 0;

  my $PROTO;

  if ($DST =~ /^([^:]*):.*/i) { $PROTO = $1 };
  if ($PROTO eq "file") {
    my $REMOTEDST;
    my $REMOTEDIR;
    if ($DST =~ /^[^:]*:\/\/(.*)/i) { $REMOTEDST = $1 };
    $REMOTEDIR = dirname($REMOTEDST);
    mkpath([$REMOTEDIR],1,0750);
    copy($SRC,$REMOTEDST);
    if (! -e $REMOTEDST) {
      $RC=1;
    };
  } elsif (($PROTO eq "http") || ($PROTO eq "https")) {
    local_wpost($SRC, $DST); 
  } else {
    nice_die(2, "Protocol ${PROTO} is not supported\n"); 
  };

  return($RC)
}

sub setConfigurationVariables {
  print("Fetching configuration from central configuration repository.\n");

  my @REPO_URLS = (
    "${REPO}/config/domains/${DOMAIN}.conf",
    "${REPO}/config/classes/${CLASS}.conf",
    "${REPO}/config/domains/${DOMAIN}/classes/${CLASS}.conf",
    "${REPO}/config/hosts/${FQDN}.conf"
  );

  foreach $REPO_URL (@REPO_URLS) {
    if (copyResourceToLocal($REPO_URL, catfile("${TMPDIR}", "config")) == 0) {
      if (file_contains("^platform=", catfile("${TMPDIR}", "config")) > 0) {
        my $result=file_show_value_cleaned("platform", catfile("${TMPDIR}", "config"));
        $PLATFORM=$result;
      };
      if (file_contains("^resultrepo=", catfile("${TMPDIR}", "config")) > 0) {
        $RESULTREPO=file_show_value("resultrepo", catfile("${TMPDIR}", "config"));
      };
      if (file_contains("^scapscanneroval=", catfile("${TMPDIR}", "config")) > 0) {
        $SCAPSCANOVAL=file_show_value("scapscanneroval", catfile("${TMPDIR}", "config"));
      };
      if (file_contains("^scapscanneroval_noid=", catfile("${TMPDIR}", "config")) > 0) {
        $SCAPSCANOVAL_NOID=file_show_value("scapscanneroval_noid", catfile("${TMPDIR}","config"));
      };
      if (file_contains("^scapscannerxccdf=", catfile("${TMPDIR}", "config")) > 0) {
        $SCAPSCANXCCDF=file_show_value("scapscannerxccdf", catfile("${TMPDIR}", "config"));
      };
      if (file_contains("^scapscannerxccdf_noprofile=", catfile("${TMPDIR}", "config")) > 0) {
        $SCAPSCANXCCDF_NOPROFILE=file_show_value("scapscannerxccdf_noprofile", catfile("${TMPDIR}", "config"));
      };
      if (file_contains("^keywords=", catfile("${TMPDIR}", "config")) > 0) {
        my $value = file_show_value("keywords", catfile("${TMPDIR}", "config"));
        $KEYWORDS="${KEYWORDS},${value}"
      };
    };
    unlink(catfile("${TMPDIR}", "config"));
  };

  print("PLATFORM                = ${PLATFORM}\n");
  print("RESULTREPO              = ${RESULTREPO}\n");
  print("KEYWORDS                = ${KEYWORDS}\n");
  print("SCAPSCANOVAL            = ${SCAPSCANOVAL}\n");
  print("SCAPSCANOVAL_NOID       = ${SCAPSCANOVAL_NOID}\n");
  print("SCAPSCANXCCDF           = ${SCAPSCANXCCDF}\n");
  print("SCAPSCANXCCDF_NOPROFILE = ${SCAPSCANXCCDF_NOPROFILE}\n");
  print("\n");
};

sub getStreamList {
  print("Getting list of SCAP data streams to evaluate\n");

  my @REPO_URLS = (
    "${REPO}/stream/hosts/${FQDN}/list.conf",
    "${REPO}/stream/domains/${DOMAIN}/classes/${CLASS}/platforms/${PLATFORM}/list.conf",
    "${REPO}/stream/domains/${DOMAIN}/classes/${CLASS}/list.conf",
    "${REPO}/stream/classes/${CLASS}/platforms/${PLATFORM}/list.conf",
    "${REPO}/stream/classes/${CLASS}/list.conf",
    "${REPO}/stream/domains/${DOMAIN}/list.conf"
  );

  foreach $REPO_URL (@REPO_URLS) {
    if (copyResourceToLocal($REPO_URL, catfile("${TMPDIR}", "sublist")) == 0) {
      local_file_append(catfile("${TMPDIR}", "sublist"), catfile("${TMPDIR}", "list"));
    };
  };

  foreach $KEYWORD (split(',', $KEYWORDS)) {
    if (copyResourceToLocal("${REPO}/stream/keywords/${KEYWORD}/list.conf", catfile("${TMPDIR}", "sublist")) == 0) {
      local_file_append(catfile("${TMPDIR}", "sublist"), catfile("${TMPDIR}", "list"));
    };
  };

  if (! -e catfile("${TMPDIR}", "list")) { open FILEHANDLE, ">" . catfile("${TMPDIR}", "list"); close FILEHANDLE; };
  open(FILEHANDLE, "<" . catfile("${TMPDIR}", "list"));
  my(@lines) = <FILEHANDLE>;
  @lines = sort(@lines);
  close(FILEHANDLE);

  open(FILEHANDLE, ">" . catfile("${TMPDIR}", "list"));
  foreach $line (@lines) {
    print FILEHANDLE $line;
  };
  close(FILEHANDLE);
  
  print("\n");
};

if ( "$ARGV[0]" eq "-d" ) {
  $PORT=$ARGV[1];
  $REPO=$ARGV[2];
} else {
  $REPO=$ARGV[0];
};

if (!defined($REPO)) {
  print("Usage: pmcsa.pl [ -d <port> ] <repository>\n");
  exit(1);
};

$CLASS="unix"; # For starters
if (File::Spec->devnull() eq "nul") {
	$CLASS="windows";
};
$DOMAIN;
if (!defined($DOMAIN)) {
  $DOMAIN="localdomain";
}
$FQDN=hostname();
$FQDN.=".${DOMAIN}";
if ($REPO =~ /^([^:]*):\/\/.*/i) { $REPOTYPE = $1; };

print("Poor Man Central SCAP Agent v0.1\n");
print("\n");

print("Detected local variables from system.\n");
print("REPO      = ${REPO}\n");
print("FQDN      = ${FQDN}\n");
print("DOMAIN    = ${DOMAIN}\n");
print("CLASS     = ${CLASS}\n");
print("PORT      = ${PORT}\n");
print("LOCALDATE = ${LOCALDATE}\n");
print("\n");

# Retrieve configuration variables from central configuration repository
setConfigurationVariables;

if (defined($PORT)) {
  daemonize();
} else {
  getStreamList();
  evaluateStreams();
}

chdir($CDIR);

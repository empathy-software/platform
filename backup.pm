
use strict;
use warnings;
use DateTime;
use Digest::MD5 qw(md5 md5_base64 md5_hex);
use Data::Dumper;

my $name;
my $action;
my $id;


if (!defined($ARGV[0])) {
    die "No project name specified.", "\n";
} else {
    $name = $ARGV[0];
}

if (!defined($ARGV[1])) {
    die "No project id specifified.", "\n";
} else {
    $id = md5_hex($ARGV[1]);
}

if (
    !defined($ARGV[2]) ||
    !($ARGV[2] eq 'save' ||
    $ARGV[2] eq 'restore')
) {
    die "No valid action.", "\n";
} else {
    $action = $ARGV[2];
}

if ($action eq 'save') {
    prepare($name, $id);
} else {
    restore($name, $id);
}

sub ex {
    my ($cmd) = @_;
    `$cmd`
}


sub prepare {
    my ($name, $id) = @_;
    
    ex("mkdir -p ./tmp/backup");
    ex("docker exec -t -u www-data app-$id php ./vendor/bin/empathy --mysql dump");
    ex("tar -cvzf ./tmp/backup/uploads-snap.tar.gz ./project/public_html/uploads");
    ex("cp project/dump.sql ./tmp/backup");
    ex("zip -r ./tmp/backup.zip ./tmp/backup");

    my $now    = DateTime->now;
    my $year   = $now->year;
    my $month  = $now->month;
    my $day    = $now->day;
    my $hour   = $now->hour;
    my $minute = $now->minute;
    my $url    = "s3://mikejw.web-backup/$name/backup.$year.$month.$day.$hour.$minute.zip";
    ex("aws --region eu-west-1 s3 cp ./tmp/backup.zip $url");
    ex("rm -rf ./tmp");
}

sub restore {
    my ($name, $id) = @_;
    my @backups = `aws s3 ls s3://mikejw.web-backup/$name/`;
    my $target;
    my @targetArr;
    my $index = 0;
    for my $item (@backups) {
        if ($index + 1 eq @backups) {
            @targetArr = split(/\s/, $item);
            $target = @targetArr[@targetArr - 1];
        }
        $index++;
    }
    
    ex("mkdir -p ./tmp/backup");
    ex("aws s3 cp s3://mikejw.web-backup/$name/$target ./tmp/backup.zip");
    ex("unzip -oj ./tmp/backup.zip -d ./tmp/backup/");

    ex("mkdir -p ./project/public_html/uploads");
    ex("rm -rf ./project/public_html/uploads/*");
    
    ex("tar -xvf ./tmp/backup/uploads-snap.tar.gz --strip-components 4 --directory ./project/public_html/uploads");
    ex("cp ./tmp/backup/dump.sql ./project");
    ex("docker exec -t -u www-data app-$id php ./vendor/bin/empathy --mysql populate");
    ex("rm -rf ./tmp")
}

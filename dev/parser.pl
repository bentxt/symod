
__END__
sub parse_conf {
    my $lines = shift;
    my ($blocks, $blk_head, $blk_fill, @blk_body);

    foreach my $ln (@$lines){
        $ln =~ s/^\s+//;
        $ln =~ s/\s+$//;
        $ln =~ s/\s+/ /;
        my @words = split ' ', $ln;
        if(@words){
            if($words[0] =~ /^[A-Z]+/){
                my ($hd, $bodyt) = (@words == 2)
                    ? @words
                    : die "Err: wrong header"
                    ;
                if($bodyt eq '['){
                    $blk_fill = sub { [ @_ ] }
                }elsif($bodyt eq '{'){
                    $blk_fill = sub { { @_ } }
                }else{
                    die "Err: wrong bodytype def"
                }
            }elsif(shift @words eq '{'){
                if(pop @words eq '}'){
                }else{
                    die "Err: wrong terminator"
                }
            };
        }else{
            $blocks->{$blk_head} = $blk_fill->(@blk_body);
            $blk_head = $blk_fill = @blk_body = undef;
        }
    }

}
#################
{ 
Aliases  => { 
    f => "functional", 
    u => "utils"
},

Exports => [
    { utils.scm => [ "echo" ]  }
]
}


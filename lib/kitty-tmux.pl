# Filter stdout mpv --vo=kitty untuk tmux. Arg: baris & kolom awal pane di layar terminal.
# mpv 0.41 cuma membungkus kepala escape kitty untuk tmux, isi gambarnya bocor jadi teks di pane.
# Di sini tiap paket kitty dibungkus utuh bersama posisi kursornya (tmux mengembalikan kursornya
# sendiri di antara paket passthrough), dan gambar dihapus dari layar saat mpv keluar
# (sebelum mpv keluar dari layar alternatif, karena sesudahnya tmux membuang passthrough).
$| = 1;
$/ = "\e\\";
my ($top, $left) = @ARGV;
my $cup = "";
my $wrap = sub { (my $s = shift) =~ s/\e/\e\e/g; "\ePtmux;$s\e\\" };
while (my $r = <STDIN>) {
  $cup = sprintf("\e[%d;%dH", ($1 || 1) + $top, ($2 || 1) + $left) while $r =~ /\e\[(\d+);(\d+)f/g;
  $r =~ s/\e_G(.*)\e\\\z/$wrap->("$cup\e_G$1\e\\")/se;
  # Sisa terakhir (tanpa penutup): mpv menulis "\e_Ga=d;" tanpa ESC \ saat keluar, dan itu
  # membuat tmux menelan paket berikutnya. Buang saja, penghapusan dikirim di bawah.
  $r =~ s/\e_G[^\e]*//g unless $r =~ /\e\\\z/;
  $r =~ s/(?=\e\[\?1049l)/$wrap->("\e_Ga=d\e\\")/e;
  print $r;
}

{
  adwaita = {
    dependencies = ["gtk4" "rake"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1s6fdw4dri5z0nrz86dkhcgx73z5fp20pr5x34wkm7cwgc3is9q9";
      type = "gem";
    };
    version = "4.3.9";
  };
  atk = {
    dependencies = ["glib2" "rake"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0s9lxaz66x45mkc1zac8bhi6q9lca73hwk0jjsha6ihmvkjkpm7n";
      type = "gem";
    };
    version = "4.3.9";
  };
  cairo = {
    dependencies = ["pkg-config" "red-colors"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "08x6f2idyfnylq0b66mqi8lf5mjvff2y2q02n5hq0x4i3ha5cwz5";
      type = "gem";
    };
    version = "1.18.5";
  };
  cairo-gobject = {
    dependencies = ["cairo" "glib2"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1j45dmxyjr3cpjgm2cfmlv4a0qaw67ivi4b6863xv3l928c974zh";
      type = "gem";
    };
    version = "4.3.9";
  };
  fiddle = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1vifygrkw22gcd4wzh8gc4pv6h1zpk6kll6mmprrf5174wvfxa3z";
      type = "gem";
    };
    version = "1.1.8";
  };
  gdk4 = {
    dependencies = ["cairo-gobject" "gdk_pixbuf2" "pango" "rake"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0jwd1j0bnprcdy3fpn3jr0wx8bvqimir1k31asjd52qlmm886ar3";
      type = "gem";
    };
    version = "4.3.9";
  };
  gdk_pixbuf2 = {
    dependencies = ["gio2" "rake"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1g1wdf0vcqlzn3a0bw47v59rl292pk8ra61mdgpxrm773nrg4y0v";
      type = "gem";
    };
    version = "4.3.9";
  };
  gio2 = {
    dependencies = ["fiddle" "gobject-introspection"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1k0azkgnlc7jim5ms2zb39a94qzlvjcaa77xzhr07cmy0pnbmp3d";
      type = "gem";
    };
    version = "4.3.9";
  };
  glib2 = {
    dependencies = ["native-package-installer" "pkg-config"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1ka9jmipfa1adf47l8831mflmjz20chiybz6z4s5wbl1gr2dph9j";
      type = "gem";
    };
    version = "4.3.9";
  };
  gobject-introspection = {
    dependencies = ["glib2"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0sympmqqfh9hcfc2hiig0c5raiiaz1r33si87xl73cczp5lhx72h";
      type = "gem";
    };
    version = "4.3.9";
  };
  graphene1 = {
    dependencies = ["gobject-introspection"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "01cc5igxiy9drr0di3pxwy3dgmck4k9wxrypnnfll945rxxypfiy";
      type = "gem";
    };
    version = "4.3.9";
  };
  gsk4 = {
    dependencies = ["gdk4" "graphene1"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "19if1cc2lkk5jcndg8iwcfs4s9gz0p3nim03lp0s53y03q7mc7wg";
      type = "gem";
    };
    version = "4.3.9";
  };
  gtk4 = {
    dependencies = ["atk" "gdk4" "gsk4"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0fs57vyk1wwn9qk0icrhsiafy4j64m3j0mcicqz71vs7wd19ax1y";
      type = "gem";
    };
    version = "4.3.9";
  };
  json = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1pqrpn0wkxvhcrwm4i0z9ailjj7if45zkkih0hij2k1q25xpwvcf";
      type = "gem";
    };
    version = "3.0.2";
  };
  matrix = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0nscas3a4mmrp1rc07cdjlbbpb2rydkindmbj3v3z5y1viyspmd0";
      type = "gem";
    };
    version = "0.4.3";
  };
  native-package-installer = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0bvr9q7qwbmg9jfg85r1i5l7d0yxlgp0l2jg62j921vm49mipd7v";
      type = "gem";
    };
    version = "1.1.9";
  };
  pango = {
    dependencies = ["cairo-gobject" "gobject-introspection"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "163scygydszb5njajq97h2bxa793jiwwi9pnsy9ddwy7vqx04yqz";
      type = "gem";
    };
    version = "4.3.9";
  };
  pkg-config = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0cy75ssbwjzi9z3zwfx2zq3b8xvpy9rbdf1rnhi3v612acfgiy9k";
      type = "gem";
    };
    version = "1.6.5";
  };
  rake = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "009p524zl0p0kfa65nii8wdmaigkmawv9pbvlcffky7islmmp0nb";
      type = "gem";
    };
    version = "13.4.2";
  };
  red-colors = {
    dependencies = ["json" "matrix"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "06ddk6dr7h3w3qvz18795md3nbh2c52bm1bl8vz3ac44s41zccqa";
      type = "gem";
    };
    version = "0.5.0";
  };
}

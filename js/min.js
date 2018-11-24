console.log("%cL M A O\n%chttps://github.com/username","color:#666;font-weight:bold;font-size:21px;line-height:2;","color:#4078c0;font-size:14px;line-height:2;");

var hosts = [
  "serain.github.io",
  "alex.kaskaso.li"
];

for (let host of hosts) {
  if ((host == window.location.host) && (window.location.protocol != "https:"))
    window.location.protocol = "https";
}

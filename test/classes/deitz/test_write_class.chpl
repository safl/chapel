class C: Writer {
  var data: string;
  proc writePrimitive(x) {
    var s = x:string;
    data += s.substring(1);
  }
  proc writeThis(x: Writer) {
    x.write(data);
  }
}

var c = new C();

c.write(41, 32, 23, 14);

writeln(c);

delete c;

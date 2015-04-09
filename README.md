# embaked
D library to bake HTML, CSS, and images into simple HTML.

This is useful for sending nice HTML emails with low spam score.

Uses [htmld](https://github.com/eBookingServices/htmld) and [cssd](https://github.com/eBookingServices/cssd).

Example usage:
```d
import embaked;

auto baked = embake(`
  <html>
    <style>
      h1 {
        background:black;
      }
    </style>
    <link rel=stylesheet href="/css/email.css" />
    <body>
      <h1>mooooo</h1>
      <img src="/flags/PT.png" alt="pt" />
    </body>
  </html>`, Options.Default | Options.BakeContentID, [ "/var/local/www/assets/" ]);

  writeln(baked.html);
  foreach(c; baked.content)
    writeln("replaced content: ", c.id); // c.content, c.mime, c.encoding also available
```

Output:
```html
<html>
  <body style="background-color:#fff;color:#343a3f;font-family:Arial;font-size:14px;line-height:18px;margin:0;">
    <h1 style="background:black;font-family:Arial;font-weight:700;line-height:18px;margin:9px 0;">mooooo</h1>
    <img src="cid:dedce7cf4811cb3ae93044d400b3d603" />
  </body>
</html>
replaced content: dedce7cf4811cb3ae93044d400b3d603
```

module embaked.embaked;

import std.array;
import std.ascii;
import std.base64;
import std.file;
import std.path;
import std.range;
import std.regex;
import std.string;

import css.parser;
import html;


enum Options {
	BakeImages		= 1 << 0,
	BakeStyles		= 1 << 1,
	BakeContentID	= 1 << 2,	// bake images but replace them and any inline images with a generated content-id

	Default = BakeImages | BakeStyles,
}


static __gshared Selector allWithClassAttr_ = Selector.parse("[class]");


struct EmbeddedContent {
	const(char)[] id;
	const(char)[] mime;
	const(char)[] encoding;
	const(char)[] content;
}


struct EmbakeResult {
	const(char)[] html;
	EmbeddedContent[] content;
}

EmbakeResult embake(const(char)[] source, Options options, const(char)[][] search = null) {
	auto app = appender!(const(char)[]);
	auto content = embake(source, options, app, search);
	return EmbakeResult(app.data, content);
}

EmbeddedContent[] embake(Appender)(const(char)[] source, Options options, ref Appender app, const(char)[][] search = null) {
	auto doc = createDocument!(DOMCreateOptions.Default & ~DOMCreateOptions.DecodeEntities)(source);
	auto content = embake(doc, options, search);
	doc.root.innerHTML(app);
	return content;
}


__gshared static auto pattern = ctRegex!(`data:([^;]+);([^,]+),(.*)`, "gis");

EmbeddedContent[] embake(ref Document doc, Options options, const(char)[][] search = null) {
	EmbeddedContent[] content;

	if ((options & Options.BakeImages) != 0) {
		foreach (img; doc.elementsByTagName("img")) {
			auto src = img.attr("src");
			if (src.empty)
				continue;

			if (options & Options.BakeContentID) {
				EmbeddedContent image;

				if (src.indexOf("data:") == 0) {
					auto matches = src.matchFirst(pattern);
					if (matches.empty)
						continue;

					image.mime = matches[1];
					image.encoding = matches[2];
					image.content = matches[3];
				} else {
					image.mime = extensionToMimeType(extension(src));
					if (image.mime.empty)
						continue;

					auto data = loadFile(src, search);
					if (data.empty)
						continue;

					image.encoding = "base64";
					image.content = mimeEncode(data);
				}

				image.id = generateCID(cast(ubyte[])image.content);
				img.attr("src", "cid:" ~ image.id);

				auto duplicate = false;
				foreach(ref c; content) {
					if (c.id == image.id) {
						duplicate = true;
						break;
					}
				}

				if (!duplicate)
					content ~= image;
			} else {
				if (src.indexOf("data:") == 0)
					continue;

				auto source = loadFile(src, search);
				if (source.empty)
					continue;

				auto mime = extensionToMimeType(extension(src));
				if (mime.empty)
					continue;

				img.attr("src", "data:" ~ mime ~ ";base64," ~ mimeEncode(source));
			}
		}
	}

	if ((options & Options.BakeStyles) != 0) {
		Style[] styles;
		styles.reserve(128);

		NodeWrapper!Node[] useless;
		auto handler = CSSHandler(styles);

		foreach (style; doc.elementsByTagName("style")) {
			parseCSS(style.text, handler);

			useless ~= style;
		}

		foreach (link; doc.elementsByTagName("link")) {
			auto rel = link.attr("rel");
			if (rel.toLower != "stylesheet")
				continue;

			auto href = link.attr("href");
			if (href.empty)
				continue;

			auto source = loadFile(href, search);
			if (source.length) {
				parseCSS(cast(char[])source, handler);
				useless ~= link;
			}
		}

		// iterate in reverse order to avoid double destruction
		foreach(node; useless.retro)
			node.destroy;

		foreach(style; styles) {
			foreach(element; doc.querySelectorAll(style.selector)) {
				HTMLString curr = std.string.strip(element.attr("style"));
				if (!curr.empty && curr.back != ';')
					curr ~= ';';

				if (curr.empty || (curr.length < style.properties.length) || (curr.lastIndexOf(style.properties) < (curr.length - style.properties.length))) {
					curr ~= style.properties;
					element.attr("style", curr);
				}
			}
		}

		foreach(element; doc.querySelectorAll(allWithClassAttr_)) {
			element.removeAttr("class");
		}
	}

	return content;
}


private struct Style {
	Selector selector;
	const(char)[] selectorSource;
	const(char)[] properties;
}


struct CSSHandler {
	this(ref Style[] styles) {
		styles_ = &styles;
	}

	void onSelector(const(char)[] data) {
		selectors_ ~= data;
	}

	void onSelectorEnd() {
	}

	void onBlockEnd() {
		if (!app_.data.empty) {
			auto style = app_.data.dup;
			app_.clear;

			foreach(selector; selectors_) {
				*styles_ ~= Style(Selector.parse(selector), selector, style);
			}
		}
		selectors_.length = 0;
	}

	void onPropertyName(const(char)[] data) {
		prop_ = data;
		value_.length = 0;
	}

	void onPropertyValue(const(char)[] data) {
		value_ ~= data;
	}

	void onPropertyValueEnd() {
		app_.put(prop_);
		app_.put(':');
		app_.put(value_);
		app_.put(';');

		prop_.length = 0;
		value_.length = 0;
	}

	void onComment(const(char)[] data) {
	}

private:
	Appender!(char[]) app_;

	Style[]* styles_;
	const(char)[][] selectors_;
	const(char)[] prop_;
	const(char)[] value_;
}

const(char)[] stripUTFbyteOrderMarker(const(char)[] x) {
	if (x.length >= 3 && (x[0] == 0xef) && (x[1] == 0xbb) && (x[2] == 0xbf))
		return x[3..$];
	return x;
}

const(ubyte)[] loadFile(const(char)[] fileName, const(char)[][] search, bool binary = false) {
	auto protocolLength = fileName.indexOf("://");
	if (protocolLength != -1) {
		auto start = fileName.indexOf('/', protocolLength + 3);
		if (start == -1)
			return null;
		fileName = fileName[start..$];
	}

	if (fileName.empty)
		return null;

	if (fileName[0] == '/')
		fileName = fileName[1..$];

	if (fileName.empty)
		return null;

	if (exists(fileName)) {
		if (!binary) {
			return cast(ubyte[])((cast(char[])read(fileName)).stripUTFbyteOrderMarker);
		} else {
			return cast(ubyte[])read(fileName);
		}
	}

	foreach(path; search) {
		auto name = buildNormalizedPath(path, fileName);
		if (exists(name)) {
			if (!binary) {
				return cast(ubyte[])((cast(char[])read(name)).stripUTFbyteOrderMarker);
			} else {
				return cast(ubyte[])read(name);
			}
		}
	}

	return null;
}


const(char)[] extensionToMimeType(const(char)[] ext) {
    switch(ext.toLower()) {
        case ".jpg":
        case ".jpeg":
            return "image/jpeg";
        case ".png":
            return "image/png";
        case ".gif":
            return "image/gif";
        default:
            break;
    }
    return null;
}


const(char)[] mimeEncode(const(ubyte)[] input) {
    auto mime = appender!(char[]);
    foreach (ref encoded; Base64.encoder(chunks(cast(ubyte[])input, 57))) {
        mime.put(encoded);
        mime.put("\r\n");
    }
    return mime.data();
}


const(char)[] generateCID(const(ubyte)[] content) {
    import std.digest.md;
    return md5Of(content).toHexString!(Order.increasing, LetterCase.lower)();
}

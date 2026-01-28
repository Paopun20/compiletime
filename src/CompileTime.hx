/****
 * Copyright (c) 2013 Jason O'Neil
 * Enhanced version with additional features and improvements
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 *
****/

import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.Format;
import haxe.Json;
#if yaml
import yaml.Yaml;
import yaml.Parser;
import yaml.Renderer;
import yaml.util.ObjectMap;
#end

using StringTools;
using Lambda;

class CompileTime {
	/** Inserts a date object of the date and time that this was compiled */
	macro public static function buildDate():ExprOf<Date> {
		var date = Date.now();
		var year = toExpr(date.getFullYear());
		var month = toExpr(date.getMonth());
		var day = toExpr(date.getDate());
		var hours = toExpr(date.getHours());
		var mins = toExpr(date.getMinutes());
		var secs = toExpr(date.getSeconds());
		return macro new Date($year, $month, $day, $hours, $mins, $secs);
	}

	/** Returns a string of the date and time that this was compiled */
	macro public static function buildDateString():ExprOf<String> {
		return toExpr(Date.now().toString());
	}

	/** Returns a Unix timestamp of when this was compiled */
	macro public static function buildTimestamp():ExprOf<Float> {
		return toExpr(Date.now().getTime());
	}

	/** Returns a string of the current git sha1 (short) */
	macro public static function buildGitCommitSha():ExprOf<String> {
		return toExpr(getGitInfo('log', ["--pretty=format:%h", '-n', '1']));
	}

	/** Returns a string of the current git sha1 (full) */
	macro public static function buildGitCommitShaLong():ExprOf<String> {
		return toExpr(getGitInfo('log', ["--pretty=format:%H", '-n', '1']));
	}

	/** Returns the current git branch name */
	macro public static function buildGitBranch():ExprOf<String> {
		return toExpr(getGitInfo('rev-parse', ['--abbrev-ref', 'HEAD']));
	}

	/** Returns the git commit message */
	macro public static function buildGitCommitMessage():ExprOf<String> {
		return toExpr(getGitInfo('log', ["--pretty=format:%s", '-n', '1']));
	}

	/** Returns whether the git working directory is clean */
	macro public static function buildGitIsClean():ExprOf<Bool> {
		var status = getGitInfo('status', ['--porcelain']);
		return toExpr(status == "" || status == "unknown");
	}

	/** Reads a file at compile time, and inserts the contents into your code as a string.  The file path is resolved using `Context.resolvePath`, so it will search all your class paths */
	macro public static function readFile(path:String):ExprOf<String> {
		return toExpr(loadFileAsString(path));
	}

	/** Reads a file at compile time and returns it as a ByteArray/Bytes */
	macro public static function readFileBytes(path:String):ExprOf<haxe.io.Bytes> {
		return toExpr(loadFileAsBytes(path));
	}

	/** Reads a file at compile time, and inserts the contents into your code as an interpolated string, similar to using 'single $quotes'.  */
	macro public static function interpolateFile(path:String):ExprOf<String> {
		return Format.format(toExpr(loadFileAsString(path)));
	}

	/** Same as readFile, but checks that the file is valid Json */
	macro public static function readJsonFile(path:String):ExprOf<String> {
		var content = loadFileAsString(path);
		validateJson(content, path);
		return toExpr(content);
	}

	/** Parses a JSON file at compile time and returns it as a typed object */
	macro public static function parseJsonFile(path:String):ExprOf<{}> {
		var content = loadFileAsString(path);
		var obj = validateJson(content, path);
		return toExpr(obj);
	}

	#if yaml
	/** Parses a YAML file at compile time and returns it as an object */
	macro public static function parseYamlFile(path:String) {
		var content = loadFileAsString(path);
		var data = try {
			Yaml.parse(content, Parser.options().useObjects());
		} catch (e:Dynamic) {
			return haxe.macro.Context.error('YAML from $path failed to parse: $e', Context.currentPos());
		}
		var s = haxe.Json.stringify(data);
		var json = haxe.Json.parse(s);
		return toExpr(json);
	}
	#end

	/** Same as readFile, but checks that the file is valid Xml */
	macro public static function readXmlFile(path:String):ExprOf<String> {
		var content = loadFileAsString(path);
		validateXml(content, path);
		return toExpr(content);
	}

	#if markdown
	/** Reads a Markdown file and converts it to HTML at compile time */
	macro public static function readMarkdownFile(path:String):ExprOf<String> {
		var content = loadFileAsString(path);
		try {
			content = Markdown.markdownToHtml(content);
			Xml.parse(content);
		} catch (e:Dynamic) {
			haxe.macro.Context.error('Markdown from $path did not produce valid XML: $e', Context.currentPos());
		}
		return toExpr(content);
	}
	#end

	/** Gets the contents of a directory at compile time */
	macro public static function readDirectory(path:String):ExprOf<Array<String>> {
		try {
			var p = Context.resolvePath(path);
			Context.registerModuleDependency(Context.getLocalModule(), p);
			var files = sys.FileSystem.readDirectory(p);
			return toExpr(files);
		} catch (e:Dynamic) {
			return haxe.macro.Context.error('Failed to read directory $path: $e', Context.currentPos());
		}
	}

	/** Checks if a file exists at compile time */
	macro public static function fileExists(path:String):ExprOf<Bool> {
		try {
			var p = Context.resolvePath(path);
			var exists = sys.FileSystem.exists(p);
			return toExpr(exists);
		} catch (e:Dynamic) {
			return toExpr(false);
		}
	}

	/** Gets an environment variable at compile time */
	macro public static function getEnv(name:String, ?defaultValue:String):ExprOf<String> {
		var value = Sys.getEnv(name);
		if (value == null) {
			value = defaultValue != null ? defaultValue : "";
		}
		return toExpr(value);
	}

	/** Gets a define value at compile time */
	macro public static function getDefine(name:String, ?defaultValue:String):ExprOf<String> {
		var value = Context.definedValue(name);
		if (value == null) {
			value = defaultValue != null ? defaultValue : "";
		}
		return toExpr(value);
	}

	/** Returns true if a define is set */
	macro public static function isDefined(name:String):ExprOf<Bool> {
		return toExpr(Context.defined(name));
	}

	/** Import a package at compile time.  Is a simple mapping to haxe.macro.Compiler.include(), but means you don't have to wrap your code in conditionals. */
	macro public static function importPackage(path:String, ?recursive:Bool = true, ?ignore:Array<String>, ?classPaths:Array<String>) {
		haxe.macro.Compiler.include(path, recursive, ignore, classPaths);
		return toExpr(0);
	}

	/** Returns an Array of Classes.  By default it will return all classes, but you can also search for classes in a particular package,
		classes that extend a particular type, and you can choose whether to look for classes recursively or not. */
	macro public static function getAllClasses<T>(?inPackage:String, ?includeChildPackages:Bool = true,
			?extendsBaseClass:ExprOf<Class<T>>):ExprOf<Iterable<Class<T>>> {
		#if (haxe_ver < 4.0)
		Context.onMacroContextReused(function() {
			allClassesSearches = new Map();
			return true;
		});
		#end
		if (Lambda.count(allClassesSearches) == 0) {
			Context.onGenerate(checkForMatchingClasses);
		}

		var baseClass:ClassType = getClassTypeFromExpr(extendsBaseClass);
		var baseClassName:String = (baseClass == null) ? "" : baseClass.pack.join('.') + '.' + baseClass.name;
		var listID = '$inPackage,$includeChildPackages,$baseClassName';
		allClassesSearches[listID] = {
			inPackage: inPackage,
			includeChildPackages: includeChildPackages,
			baseClass: baseClass
		};

		if (extendsBaseClass != null)
			return macro CompileTimeClassList.getTyped($v{listID}, $extendsBaseClass);
		else
			return macro CompileTimeClassList.get($v{listID});
	}

	/** Returns the Haxe compiler version as a string */
	macro public static function getHaxeVersion():ExprOf<String> {
		return toExpr(Context.definedValue("haxe"));
	}

	/** Returns the current platform/target being compiled for */
	macro public static function getTarget():ExprOf<String> {
		var target = #if windows
		"windows"
		#elseif linux
		"linux"
		#elseif mac
		"mac"
		#elseif ios
		"ios"
		#elseif android
		"android"
		#elseif wasm
		"wasm"
		#elseif native
		"native"
		#else
		"unknown"
		#end;
		
		return toExpr(target);
	}

	#if macro
	static function toExpr(v:Dynamic) {
		return Context.makeExpr(v, Context.currentPos());
	}

	static function loadFileAsString(path:String):String {
		try {
			var p = Context.resolvePath(path);
			Context.registerModuleDependency(Context.getLocalModule(), p);
			return sys.io.File.getContent(p);
		} catch (e:Dynamic) {
			return haxe.macro.Context.error('Failed to load file $path: $e', Context.currentPos());
		}
	}

	static function loadFileAsBytes(path:String):haxe.io.Bytes {
		try {
			var p = Context.resolvePath(path);
			Context.registerModuleDependency(Context.getLocalModule(), p);
			return sys.io.File.getBytes(p);
		} catch (e:Dynamic) {
			return haxe.macro.Context.error('Failed to load file $path: $e', Context.currentPos());
		}
	}

	static function validateJson(content:String, path:String):Dynamic {
		try {
			return Json.parse(content);
		} catch (e:Dynamic) {
			return haxe.macro.Context.error('JSON from $path failed to validate: $e', Context.currentPos());
		}
	}

	static function validateXml(content:String, path:String):Xml {
		try {
			return Xml.parse(content);
		} catch (e:Dynamic) {
			return haxe.macro.Context.error('XML from $path failed to validate: $e', Context.currentPos());
		}
	}

	static function getGitInfo(command:String, args:Array<String>):String {
		try {
			var proc = new sys.io.Process('git', [command].concat(args));
			var result = proc.stdout.readLine();
			var exitCode = proc.exitCode();
			if (exitCode != 0) {
				return "unknown";
			}
			return result;
		} catch (e:Dynamic) {
			return "unknown";
		}
	}

	static function isSameClass(a:ClassType, b:ClassType):Bool {
		return (a.pack.join(".") == b.pack.join(".") && a.name == b.name);
	}

	static function implementsInterface(cls:ClassType, interfaceToMatch:ClassType):Bool {
		while (cls != null) {
			for (i in cls.interfaces) {
				if (isSameClass(i.t.get(), interfaceToMatch)) {
					return true;
				}
			}
			if (cls.superClass != null) {
				cls = cls.superClass.t.get();
			} else
				cls = null;
		}
		return false;
	}

	static function isSubClassOfBaseClass(subClass:ClassType, baseClass:ClassType):Bool {
		var cls = subClass;
		while (cls.superClass != null) {
			cls = cls.superClass.t.get();
			if (isSameClass(baseClass, cls)) {
				return true;
			}
		}
		return false;
	}

	static function getClassTypeFromExpr(e:Expr):ClassType {
		if (e == null)
			return null;

		var ct:ClassType = null;
		var fullClassName = null;
		var parts = new Array<String>();
		var nextSection = e.expr;

		while (nextSection != null) {
			var s = nextSection;
			nextSection = null;

			switch (s) {
				case EConst(c):
					switch (c) {
						case CIdent(s):
							if (s != "null") parts.unshift(s);
						default:
					}
				case EField(e, field):
					parts.unshift(field);
					nextSection = e.expr;
				default:
			}
		}

		fullClassName = parts.join(".");
		if (fullClassName != "") {
			try {
				switch (Context.follow(Context.getType(fullClassName))) {
					case TInst(classType, _):
						ct = classType.get();
					default:
						throw "Currently CompileTime.getAllClasses() can only search by package name or base class, not interface, typedef etc.";
				}
			} catch (e:Dynamic) {
				Context.warning('Could not resolve type: $fullClassName', Context.currentPos());
			}
		}
		return ct;
	}

	static var allClassesSearches:Map<String, CompileTimeClassSearch> = new Map();

	static function checkForMatchingClasses(allTypes:Array<haxe.macro.Type>) {
		var getAllClassesResult:Map<String, Array<String>> = new Map();
		for (listID in allClassesSearches.keys()) {
			getAllClassesResult[listID] = [];
		}

		for (type in allTypes) {
			switch type {
				case TInst(t, _):
					var className = t.toString();
					var classType = t.get();
					if (classType.isInterface == false) {
						for (listID in allClassesSearches.keys()) {
							var search = allClassesSearches[listID];
							if (classMatchesSearch(className, classType, search)) {
								getAllClassesResult[listID].push(className);
							}
						}
					}
				default:
			}
		}

		switch (Context.getType("CompileTimeClassList")) {
			case TInst(classType, _):
				var ct = classType.get();
				if (ct.meta.has('classLists'))
					ct.meta.remove('classLists');
				var classListsMetaArray:Array<Expr> = [];
				for (listID in getAllClassesResult.keys()) {
					var classNames = getAllClassesResult[listID];
					var itemAsArray = macro [
						$v{listID},
						$v{
							classNames.join(",")
						}
					];
					classListsMetaArray.push(itemAsArray);
				}
				ct.meta.add('classLists', classListsMetaArray, Context.currentPos());
			default:
		}

		return;
	}

	static function classMatchesSearch(className:String, classType:ClassType, search:CompileTimeClassSearch):Bool {
		if (search.inPackage != null) {
			if (search.includeChildPackages) {
				if (className.startsWith(search.inPackage + ".") == false)
					return false;
			} else {
				var re = new EReg("^" + search.inPackage + "\\.([A-Z][a-zA-Z0-9]*)$", "");
				if (re.match(className) == false)
					return false;
			}
		}

		if (search.baseClass != null) {
			if (search.baseClass.isInterface) {
				if (implementsInterface(classType, search.baseClass) == false)
					return false;
			} else {
				if (isSubClassOfBaseClass(classType, search.baseClass) == false)
					return false;
			}
		}

		return true;
	}
	#end
}

#if macro
typedef CompileTimeClassSearch = {
	inPackage:String,
	includeChildPackages:Bool,
	baseClass:ClassType
}
#end

This is a Portage overlay in which each category contains a few ebuilds 
set up to example to test package manager behaviour. 

For each category "emerge -vp -e testX/web" to execute the test. 
 

## Test case 1 - Dependencies

This scenario defines the following runtime dependencies for "web"

![Runtime Dependencies](../../Documentation/Tests/test1/web-1.0-rdepend.svg)

This scenario defines the following compiletime dependencies for "web"

![Compiletime Dependencies](../../Documentation/Tests/test1/web-1.0-depend.svg)

The result using Gentoo emerge: 

![Emerge Output](../../Documentation/Tests/test1/expected.png)


## Test case 2 - Versions

This scenario defines the following runtime dependencies for "web"

![Runtime Dependencies](../../Documentation/Tests/test2/web-2.0-rdepend.svg)

This scenario defines the following compiletime dependencies for "web"

![Compiletime Dependencies](../../Documentation/Tests/test2/web-2.0-depend.svg)

The result using Gentoo emerge: 

![Emerge Output](../../Documentation/Tests/test2/expected.png)


## Test case 3 - Self-Dependency (compile) 

This scenario defines the following runtime dependencies for "web"

![Runtime Dependencies](../../Documentation/Tests/test3/web-1.0-rdepend.svg)

This scenario defines the following compiletime dependencies for "web"

![Compiletime Dependencies](../../Documentation/Tests/test3/web-1.0-depend.svg)

The result using Gentoo emerge: 

![Emerge Output](../../Documentation/Tests/test3/expected.png)


## Test case 4 - Self-Dependency (run)

This scenario defines the following runtime dependencies for "web"

![Runtime Dependencies](../../Documentation/Tests/test4/web-1.0-rdepend.svg)

This scenario defines the following compiletime dependencies for "web"

![Compiletime Dependencies](../../Documentation/Tests/test4/web-1.0-depend.svg)

The result using Gentoo emerge: 

![Emerge Output](../../Documentation/Tests/test4/expected.png)



## Test case 5 - Self-Dependency (compile & run)

This scenario defines the following runtime dependencies for "web"

![Runtime Dependencies](../../Documentation/Tests/test5/web-1.0-rdepend.svg)

This scenario defines the following compiletime dependencies for "web"

![Compiletime Dependencies](../../Documentation/Tests/test5/web-1.0-depend.svg)

The result using Gentoo emerge: 

![Emerge Output](../../Documentation/Tests/test5/expected.png)



## Test case 6 - Circular dependency (compile)

This scenario defines the following runtime dependencies for "web"

![Runtime Dependencies](../../Documentation/Tests/test6/web-1.0-rdepend.svg)

This scenario defines the following compiletime dependencies for "web"

![Compiletime Dependencies](../../Documentation/Tests/test6/web-1.0-depend.svg)

The result using Gentoo emerge: 

![Emerge Output](../../Documentation/Tests/test6/expected.png)



## Test case 7 - Circular dependency (run)

This scenario defines the following runtime dependencies for "web"

![Runtime Dependencies](../../Documentation/Tests/test7/web-1.0-rdepend.svg)

This scenario defines the following compiletime dependencies for "web"

![Compiletime Dependencies](../../Documentation/Tests/test7/web-1.0-depend.svg)

The result using Gentoo emerge: 

![Emerge Output](../../Documentation/Tests/test7/expected.png)


## Test case 8 - Circular dependency (compile & run)

This scenario defines the following runtime dependencies for "web"

![Runtime Dependencies](../../Documentation/Tests/test8/web-1.0-rdepend.svg)

This scenario defines the following compiletime dependencies for "web"

![Compiletime Dependencies](../../Documentation/Tests/test8/web-1.0-depend.svg)

The result using Gentoo emerge: 

![Emerge Output](../../Documentation/Tests/test8/expected.png)



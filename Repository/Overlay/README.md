This is a Portage overlay in which each category contains a few ebuilds 
set up to example to test package manager behaviour. 

For each category "emerge -vp -e testX/web" to execute the test. 
 

## Test case 01 - Dependencies

This scenario defines the following runtime dependencies for "web"

![Runtime Dependencies](../../Documentation/Tests/test01/web-1.0-rdepend.svg)

This scenario defines the following compiletime dependencies for "web"

![Compiletime Dependencies](../../Documentation/Tests/test01/web-1.0-depend.svg)

The result using Gentoo emerge: 

![Emerge Output](../../Documentation/Tests/test01/expected.png)


## Test case 02 - Versions

This scenario defines the following runtime dependencies for "web"

![Runtime Dependencies](../../Documentation/Tests/test02/web-2.0-rdepend.svg)

This scenario defines the following compiletime dependencies for "web"

![Compiletime Dependencies](../../Documentation/Tests/test02/web-2.0-depend.svg)

The result using Gentoo emerge: 

![Emerge Output](../../Documentation/Tests/test02/expected.png)


## Test case 03 - Self-Dependency (compile) 

This scenario defines the following runtime dependencies for "web"

![Runtime Dependencies](../../Documentation/Tests/test03/web-1.0-rdepend.svg)

This scenario defines the following compiletime dependencies for "web"

![Compiletime Dependencies](../../Documentation/Tests/test03/web-1.0-depend.svg)

The result using Gentoo emerge: 

![Emerge Output](../../Documentation/Tests/test03/expected.png)


## Test case 04 - Self-Dependency (run)

This scenario defines the following runtime dependencies for "web"

![Runtime Dependencies](../../Documentation/Tests/test04/web-1.0-rdepend.svg)

This scenario defines the following compiletime dependencies for "web"

![Compiletime Dependencies](../../Documentation/Tests/test04/web-1.0-depend.svg)

The result using Gentoo emerge: 

![Emerge Output](../../Documentation/Tests/test04/expected.png)



## Test case 05 - Self-Dependency (compile & run)

This scenario defines the following runtime dependencies for "web"

![Runtime Dependencies](../../Documentation/Tests/test05/web-1.0-rdepend.svg)

This scenario defines the following compiletime dependencies for "web"

![Compiletime Dependencies](../../Documentation/Tests/test05/web-1.0-depend.svg)

The result using Gentoo emerge: 

![Emerge Output](../../Documentation/Tests/test05/expected.png)



## Test case 06 - Circular dependency (compile)

This scenario defines the following runtime dependencies for "web"

![Runtime Dependencies](../../Documentation/Tests/test06/web-1.0-rdepend.svg)

This scenario defines the following compiletime dependencies for "web"

![Compiletime Dependencies](../../Documentation/Tests/test06/web-1.0-depend.svg)

The result using Gentoo emerge: 

![Emerge Output](../../Documentation/Tests/test06/expected.png)



## Test case 07 - Circular dependency (run)

This scenario defines the following runtime dependencies for "web"

![Runtime Dependencies](../../Documentation/Tests/test07/web-1.0-rdepend.svg)

This scenario defines the following compiletime dependencies for "web"

![Compiletime Dependencies](../../Documentation/Tests/test07/web-1.0-depend.svg)

The result using Gentoo emerge: 

![Emerge Output](../../Documentation/Tests/test07/expected.png)


## Test case 08 - Circular dependency (compile & run)

This scenario defines the following runtime dependencies for "web"

![Runtime Dependencies](../../Documentation/Tests/test08/web-1.0-rdepend.svg)

This scenario defines the following compiletime dependencies for "web"

![Compiletime Dependencies](../../Documentation/Tests/test08/web-1.0-depend.svg)

The result using Gentoo emerge: 

![Emerge Output](../../Documentation/Tests/test08/expected.png)


## Test case 09 - Dependency on non-existent package (compile)

This scenario defines the following runtime dependencies for "web"

![Runtime Dependencies](../../Documentation/Tests/test09/web-1.0-rdepend.svg)

This scenario defines the following compiletime dependencies for "web"

![Compiletime Dependencies](../../Documentation/Tests/test09/web-1.0-depend.svg)

The unsatisfiable dependency:

![Dependency](../../Documentation/Tests/test09/os-1.0.svg)

The result using Gentoo emerge: 

![Emerge Output](../../Documentation/Tests/test09/expected.png)


## Test case 10 - Dependency on non-existent package (run)

This scenario defines the following runtime dependencies for "web"

![Runtime Dependencies](../../Documentation/Tests/test10/web-1.0-rdepend.svg)

This scenario defines the following compiletime dependencies for "web"

![Compiletime Dependencies](../../Documentation/Tests/test10/web-1.0-depend.svg)

The unsatisfiable dependency:

![Dependency](../../Documentation/Tests/test09/os-1.0.svg)

The result using Gentoo emerge: 

![Emerge Output](../../Documentation/Tests/test10/expected.png)



## Test case 11 - Dependency on non-existent package (compile & run)

This scenario defines the following runtime dependencies for "web"

![Runtime Dependencies](../../Documentation/Tests/test11/web-1.0-rdepend.svg)

This scenario defines the following compiletime dependencies for "web"

![Compiletime Dependencies](../../Documentation/Tests/test11/web-1.0-depend.svg)

The unsatisfiable dependency:

![Dependency](../../Documentation/Tests/test09/os-1.0.svg)

The result using Gentoo emerge: 

![Emerge Output](../../Documentation/Tests/test11/expected.png)

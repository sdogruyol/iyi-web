# A project of its own, so it can require the database packages without
# making them dependencies of iyi-web. `replace` builds iyi-web from this
# checkout; outside the repository, delete that line.
module todos-pg

require github.com/sdogruyol/iyi-web v0.5.1 as web
require github.com/iyilang/db v0.4.0 as db
require github.com/iyilang/pg v0.4.0 as pg

replace github.com/sdogruyol/iyi-web => ../..

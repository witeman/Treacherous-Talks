-define(SAMPLE_REGISTER,
<<"sddfaadfaff\r
REGISTER\r
NICKNAME: Lin\r
PASSWORD: QWER\r
\r
EMAIL: ss@pcs\r
asdfasdlfadf\r
\r
FULLNAME: Agner Erlang\r
END\r
adfadfasdfaldfad">>
).

-define(SAMPLE_LOGIN,
<<"sddfaadfaff\r
LOGIN\r
NICKNAME: Lin\r
PASSWORD: QWER\r
END\r
adfadfasdfaldfad">>
).

-define(SAMPLE_UPDATE,
<<"sddfaadfaff\r
UPDATE\r
NICKNAME: Lin\r
PASSWORD: QWER\r
FULLNAME: Agner Erlang\r
END\r
adfadfasdfaldfad">>
).

-define(SAMPLE_CREATE,
<<"sddfaadfaff\r
CREATE\r
----Required Fields---------\r
GAMENAME: awesome_game\r
PRESSTYPE: white\r
ORDERCIRCLE: 4H\r
RETREATCIRCLE: 3H30M\r
GAINLOSTCIRCLE: 2H40M\r
WAITTIME: 2D5H20M\r
----Optional Fields---------\r
PASSWORD: 1234
\r
END\r
adfadfasdfaldfad">>
).
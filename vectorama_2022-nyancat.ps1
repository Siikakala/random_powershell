[CmdletBinding()]
param()
if ($host.UI.RawUI.WindowSize.Width -lt 324 -or $host.UI.RawUI.WindowSize.Height -lt 70) {
    if ($null -ne $env:WT_SESSION) {
        # Windows Terminal - don't want to touch
        Write-Error "Detected Windows Terminal session and too small window!"
        Write-Host "`nOutput requires at least 324x75 characters window, please resize it manually. Your current window is: $($host.UI.RawUI.WindowSize.Width)x$($host.UI.RawUI.WindowSize.Height)`n`nRecommended method: Alt-enter to full screen, then zoom out with ctrl-minus until output fits"
        exit
    }
    else {
        try {
            $newsize = New-Object -TypeName System.Management.Automation.Host.Size -ArgumentList (324, 70)
            $host.UI.RawUI.BufferSize = $newsize
            $host.UI.RawUI.WindowSize = $newsize
        }
        catch {}
    }
}
if ($host.UI.RawUI.WindowSize.Width -lt 324 -or $host.UI.RawUI.WindowSize.Height -lt 70) {
    Write-Error "Failed to resize window to minimum size of 324x75 characters!"
    exit
}
Clear-Host
$frames = "
H4sIAHywIU8AA+1d23XkOA797xT8oxBst+11z4QyMVQO+7ExbIAbydrdVXqCeJOEKNQZnzMURIq4
BEAU6jb19M/b59/vfz/fnv78z8uvj9u0+zz98yUFrrI6PG473nX8wA/68cSYI+fze/hlNkvz9fWV
O7td9103p6kyJrq69vITeQTet6DIQY3X5094kXETYPclFS6ru37Q2w26k76jBJUPUPSHUF+vEvao
/djBVCQG0KHC1B540K2Exqve9jl9jbiVu7/9q2jih/EI2Ljj3tgIwp/DY2E41ZBJ7KcAJwtQjhUy
RnWGk1zDI9a1jZOz6OVbEZA+j/s91y0/C7soC0AeRvINC8GPAzobJOagYmOirKWMiEBzRHuL7upw
iOjO399lseP9Fx88cTcutj+PsQBwL0j4E9V9f5EThOShVxr1f9+i3zA56FEfteuZN8R1h+ciePBc
jz3cgSH9Uu+ZZmAMmRvvBj3SH5gfod5N9yQXhLtR8P0Z6i1PYwHVqA8jPSA70VtfUQUPJWx4kyPP
969nCpgQalyHRRY4zcF4tbug6umPzqYnotBRawDurjdIRkGN9T72NUxa//nx11+MAh6k6KIQWT6V
+AL8qKyHCjcFeCjfeuhqDHM1VJGWwI/Keui49VA8rWfmqmztS/GaUX7i2j6vkmrGzZA2iwp42m3b
UNDjqWkugmqyPrHp8Ue1YoY9eB6mvtmBUynhwEfiUE/hOtyqo8Fl9CV5fkhnQctZDxZ+kgExkI6r
oS+C7sO9uSjqWAvmmy8Cg2R/lwWnxhVRumoFeuBRSJVCRU7q9GONOoSvblEpYq8FAs7JBchhw1x3
8SuTBq+QOqBi2Jj8aqR0Ea3otVshp6xKrgblyBo3hnpLs1hFeZRIzUo7kngbLKhQpcbLTAvYI997
IOUywriAq8v9evdxqZXOk2lWLTWVHcEN5EbL6P547wi10pIZudNJGTPbe622PCr2TXieo5Vr1/u7
lRVq3s7AoZ2JrvRHnCPBiGS5tlO5dj2q3uBdOHEAnpoUm40T8CA492lchqQHyHLtTrexyrVLXytZ
s74NAjcd5ulRu+V8FNrywzELCc6MnNTFrPBs9dSlF58gWUhQKRQk+68seIQrpzLXSOKqgtghj7zS
8NyjaKrRio+dw4627tK2nrr04pIkiX2DKKRkDRZeGo9y4xFmyuF1jnHsncXVVWfgKnW/KFaK8Lr3
MJbc5P5AKIXg3OeZjgDtscdkdH+sN17TfPRsX9HMmqak+64bl9F73y3t/87dvIuAg2dNM2uaAhXX
Y1ormgowSDw1KSsbJ+BBcMqRNU1efpk1TY+a5tLT/s/P69sgcNNhplnTdFcXgFyyuJTaKmVhhSVU
Y8k/+WZ4odAeJFuzLK6cptypc3hpWJEHZWnkDlnupMLkqOXOpY+y2Cnw7A8m/1Hv+2aQDWldjEoo
4lcftClmjZSvId3h941MajGAMeqVt/kOSUBj43Xv4calZK+5qlO/Z56TbMr6N/KEYXqURLefLJDy
u++6xTvsk040gQdngTQLpGUVY5/SiScawU43pT9GNAxpcrwzS11wkSy9vhzKMyDGqDBmVc7cBO7b
D1rbGhnzYhRK9bVD+SJRi33Wk0gZLk7dFu8kUpfTMln2KXQU/n4us9CoZ5TiHwBhWaTRuLEszOtr
p04Y4dMb5yTSrudjat3UjJ8hbfMrf7IXhPqQmwSENTIAe1s+jCxOTq2HeB5m0PgkUsAFUOe4Afdq
MMc/20epa3eq7UnVqe8zXQDa447J6P507yYHgMo/Wdzkd991i3dyJ5UHgo/O4uZAxU0stUD1Z0Tq
8q56HwdJNPqfzmnIEH04pLbEK2a1lESNgQt3VDsuaN59/Gbdo5BKJ8w+5T6u8/U+qRNZPhgTTicm
RpIhMSCOiNtKoiocECyiHcgJj88uia5uiVnuA73rKKx+Cic/r5BHbOlm0b1+CPisLD6xdTvn24oY
eWSt4qlh42le/Cu671bochxnW38Gl7x+/ZDI2tx4oXSH+43V32vE0pcECbxhlrid6WkwI0qRsvNv
BspqaQuA5ifdcAmnN6d//SNAhZYJj3rmauUgr0vqfowoZ5vNaiVpDdjYwVQkBtChwtQeeFApMQl+
GimZlJVviEfFBHeTI9hqyCT2M0CtVmob7Y2Ts+iqUq3LeaVyL8AX/6ysTS0WEnMpI9K/PKuOh4ju
/A1eFjxCFGudzk5lbAjJ2iQ16F14LM81QkVW75lmYAypW+2KrMu5qYWe5IJwN4ozVl1hfcUa0h3u
N57z/fGomQFX4ful7rOMr9oFd9NpWJ3M98dzP/XPDxX6AjxuFkSFmwI8lG9BdJ0XNDiDtKyuJGfL
gigydjAVySE0uSpb+1K8Pt9Rpoa0OQ/vRAImnvWJTY8/qhUz7MHnf3+8yzGmep/RH3fKD+ksaDnr
AeEXgLEK3Nv/bFADEPhNFzsBNOyhq4plVYfw1S0qRfL98XVQwaeeJ3YyYV76mE8WIFeDcmSNG0O9
pVnsmMd3ilVgpgXske89ghw0aup0mFWzZ57zIE/LpLWfPD0Uuv1w35krtHl6KOsjTotgvLJCm6eH
Anhqsmo2TsCD4HQnX6/Ey22zQiuv0HqcJlruWt8GgZsOU1GUa/P1SkJlZYtLqa1SFla4zkGgxQSV
QkGy/8qCR+8Kar4yvjBGRexYWvGxc9jR1l0qllBdjgYl9o2654Q6IGlI0CqWXfOV8VJtYX0VGtId
ft/odkjo/n5prBThde+Rr4wnnjnCK+P/3JgnhlabDyPeSrvvuuWJoVnQ9FdfrxL2KL+CJtdomxwD
CgyhyVfZOAEPOuQbRe3pjxkNQzqcBU0kDOJ5ttig+KNCmHkc/1nuWt8GgZsOk8mCpru6AOSSxaXU
VikLKzzioZvSuHKaWqfO4aVhRR6UpZE7ZK2TCpOj1jqLLrwVliudAs/ufkAnDbIhrYtRBkX8Kt8X
H6xAWtZq6V66XxfQ2Hjde+T74olnnpNmWv2QUKpD6ZM1Un73Xbd4B3zSuSYwdNZIs0YqUnE9qt7g
61DMdPgxcQIeBOzaRWTojxENQ6Yc75xSF1wkS6+viPIMiDEqH7Olt/acTejG3ai1zZEzL7pYmu+M
d0eCvVgSkygjYi6qPtU7IZNln0JH4W/oMgsNcS5puPcZgc+QxXl9/dQJI3x6Q58+unStfSam1k3N
+BnyNr8SKLwg+c54ma4lfcUa0h3uN3qf6WlDH/9s55HvQyKeOcLb4wsj9/jX7lnq5HffdYt3dCeV
FIKDZ6lzoFInlmeg+jOCNbHFBj+e05Au+pBKbVlYzNopiRoDF+6odlzQJLxQE+RDJjGQ1rW/0x7V
iSwfjAmnE4xRgOM4eZFehQOCRbQTOeHxT/sC+bDHcPLzCnnElm4W3YuJgM/K4hNbt3O+roiRR17w
BfJdz+Ns68/gktcvJhJZmxtRlO5wv3G4F8jDSmzvX64id6sNilKpHAY2A2XptAVA85NuuITTm9N/
VTr9XSVbadmg+fXfz8eV//33P+GunQaX3ZS/I9la9O/H3SkdWwoYxG+TAv8ejv9dINwY1+5ho4o7
OHZ3nSPhvQXlO/kqN7/SzvvI35LDg7+zUqfmV3L/eNKXRPgkU2eyiSGAwjdDTQeCnZ1ms34TdwS2
VXzZXk2/QJtfKiB2j0truhTmBsBWie2es5O87parYXNe6k8gAAwsZoO0srRXYAOqJpWtldHhu2xt
uzl/fylGm+Xk1RQNeP7NmAWuwW7DfPj+55x2Q0YwnrRXrKun0UspXHytP8NEUKuWxCEv/6+bcBr8
Xxsd6kq1cy7Hg63VZmvngxJP8XVBwq2aOQ6Rohv86vuXdAQ7MbIB57Hyu4fP/dyg26R1n/7n8Wv3
WMKK2AHuigoPQcJrw+yVIb88o15AiFtue6Kh1LMy4QGEhY/Zmn4eF24gYevwFw6AJriKatPLjzGl
oNGuRMf62o1HmG/fU4iL6OEPJqVVRipHMki9dcViI4XgXkekrR9lS9hacP8A/KraF8X1l/djnpTS
ag56FSkYNp6W2sLSKPyBXhHgEjLnWuEc9uP9zPyejq7dcYlWtznq7P8Alloc0zzVX2P22wxyAGob
dK0ZEDVwSQpcSgsGgQSAx2hxWVPJcTuTmAApKW9Jecsm5QinoLxVZMBVo7z9+d/D9ljaMbtQ3ua1
jUdDqypuBrAb3mekscVktZV8tvTdxofZNi6rbTzeGslqw9BwqoVLcT4jzS1Zb2Ss2Nr7lVsst7Gy
2ozey/fAKIw4Pxe8DkGuKTnuPtk4vLVKworYKehw9p+N7NtwkLw8uXQihVlcugF5dEmVa4/raYlz
cH6SPDpiN6nEo0sO3ckYdWHZaWeU+rnqVaSQZX6jSFKWQG8IcAmbMzxvP+OB3bw063oMN0Tvs9Dq
MK0GZdPNCAYgtEHX3h4XprbNSBg44fKxHafkE82kG+ct/7Z97ku4C/az7z9JYlxm1hVpdrgf0QTL
qdyk2WkpbizmFluUfNmkzHVtkmV8wnI2IzfhbKqKdu0qfnxX4nJJYxPMqoqnTs3AkLTCuxcNrxpZ
1qkO6f6TguwwSYsqwHD9D6CMSfW7Gomwo7d7bc1GUp3W+dlSsijvSBJIil311rKyAM3H153ckldR
gm7dTS3O2KvJ2zZXtLiyCYwlnBq3aqhBeWxZ2ItlLQ0j7b7lVtmGV3XF91+MzVIxMIMK6zeLHiza
VSscwysCIY+V5vnzC8BlEXs8zWxT7/bdEvPvlzeWmwY/7tYX1ejIi92aRrYcW0XeiuV3DtCZLiAW
h0wrj/2MUk7QgIaYVhSXAVhjMS5N3JyNsR8D9xTGNif78D01LzXUpNqjZoNsRYBT4+8+iPvM7LOK
R9p7e1yY2jYjYVAHl2TkXZOkF5g4d0VWXpL2UsxcsCTtnbuZpL0k7XUUT52agSHphHeS9G7skZOk
l6y8ojQmKy85e3hTGwuSs3eVlp7zkxS+MKw8e0y47TfVMSl8U+NWLACqUvgYcZsZKNp9q62y7yZJ
z9gKx5+LQMtT2qaAWZe0u+29Sbtbm0a2jB6UpLwu4iTlXYKUNxF/ISYJz1u/pwNLUhjMUDEuPqry
pYaatARtNsoWLDz1crgP4j4zn1k1fhHtrjlPLwDLDbp2alzykvoSGlaGf3XrkOS284pFZNpk6Y0l
TpbeyM1k6Z2BpbdZoiSzXZE8eAYWXU/anJvDu7+QVrY/jvtm2vHIbST1rYtUhPMZ+XnRCXliul4d
gt4ummxt/kKt4m95TX95OszC0e3csls8g0+m3l2jG7R59zpBKxzFLR51sGyWptfSsqOK1NvbfVv1
2VX9iG6h6HZrrw7HXAtGiEuioQTXIah8yd0jQ8bW0LMlbC3r8wFmo0VjTMJeMvL6MfKemNQi0LYD
XCrMV5NGsVErDG7+tg3fU/NSQ006g7axj5pcOvXquA/iPjPfWTXm0s3zCkCUg641A6IVLnlJfQmN
McMT6pIxFwrvJNBdSJwEupGbFyDQrb7HAX3F1BzVpKV0OmFS0IVsN4MajwBXVdwMYDe8O7Jk2E3p
z2ysUmDBo9WhpOSzjFlpeS9zBInDdUueHF+Kc92cOKVinC9ImxM5aj2pds5JjKNbLF/h/TpUxwDO
SptTG+37Lwx36292EeYB/HCenDlHYUXsFJQ5tRENQKF7eUa9hBC33DZFQ6lnZcJjbIpesvDa4zoE
J2/VWZXFzbN+1oiLaPpFfsc9pBjKIPXWNZGNFII7KYBurReMAij8FzceP9IEJvXFYgymFAsQT0sZ
YmkAf6DtB7iEzJkXajkhHUCuMLi5ngDfU/NSQ01Uj4L2cnjJQzP/zANUmZX/zOK9yxa69va4MLVt
RsJAi4uRM5TSIaWbqxTVseM5m/fvxWEJe1dkX5IVj3VTxmSyNE3FkzYUKvE3SDqFmhdst37ZrN80
/qxoqtY5NXHOjomjZ3KpShy9GfJ47Laq4qlTs5pSL52kMqx70X0srielHbAKfeY9tTH/72psuVOw
EiW/6EgNFR4Y5hV6uXTdnNPg0lqHTwbfGC2Fp/i6IOFWzRyHyNINfnVZht59uDhEt0rCqXErHAAc
IRAIZIfneW3FvdLp5PaJFBZz+5IQdwGioageTRPy2pXlWF+dk3GXjLsztBbcxYw7I4EF+XUlpdUc
9CpSMGw8LcUE2OoDXJqIvwiTrLVvFBbN73GoVRxBXt3mqKT/A1hqtXj9bdO/eCS4t8eFqW0zEgZO
uCT/LaVH6eZqOP5bYE7aFQlvyYdzniaGQPLhTtscgA9XkR5XjQ83wdtZaYe7BB9u6tQMDEknvM/I
gYtJiSvFgKOjM2Yi/u0+OXCVpBascK6aV13dV98zMuiSUIcHh+6UtUgtllNZCXMu/+ib44FRyHZ+
Lngd7t2YvLupcSscAByhglpn/0XKvqMHyemTlydSmMXLa8fJC0eXuwILb0yKHpyfJGOPWOBKjL1k
652MuxeWB3dGqZ+rXkUKWeY3inF4exPxF2KS8Lz9zLK0TMfLfvsUhfhZGHuYVoMS9f6onOS4/bVT
45KX1Jdwl3nkaXFZX0kpG0jsTL+dyk2aSZfixmJuXUfJxU16X9cmWeYnLGczcsxX1nb5978MV+Ly
XpP51lwcEO9elLtqRFunEqT7rwmyUyotqgDDjfy22nyXbQRpECav455sJO5powxbShb+HdkDSeOr
3lpWFuDq+LqTW9Yqysyt27bFGXs1eftzrxOoAlPSOvEAFxuFiSllYS9ytjQytPvGWmVnXdUI338x
9j/FwAwGrd8sdny3cLSxy7PRmEJ/liwuBaO4ODzQ7Dn1bt8tMX95xpoGp+/WF9XoGEC2Zp8tx1aR
wWL5gQN0pguIxSHTSnA/o5QTNKAhWHyee7+IhDHhvHl5F2ObBO4pjG1O2OF7al5qqEm1R8120Iqw
psbffRD3mdln1ZhkN88lAIMOutYMiFa45CX1JTSuDM+0SypdKLyTWXchcTLrRm4msy6ZdavmjFM8
tltVcTOA3fBOpt2NPXIy7SJKk0sXAeek1mnDSlLrrtKiyHSo0NG73LLYZNppYsJtvz83ZdqVjWws
oQNaVal1jNjLdPZ2X0qr7J1JnjuLcDh+HH3Om8BRTSdXIg6fdDiBGycd7tytspNQQuYzkiznKE6y
XE+y3L3PZYhykBcDwBUGM9SEi4+qfKmhJi1Bm22hBVlOvRzug7jPzGdW8V4dC117e1yY2jYjYeCE
C8q66SDdWGgkrpznJTRMdTwR8v6lMSyD7Ip0wOTFXUmcvLiRm8mLOwMvbp5+PEZZVfHUqRkYklZ4
n4F315No5xZg3N85K9uPex9sGZNLFoQNuC7/o0bqLBWt0RmZddGpdGKiXR1q3TpARCKqdSDGwV7Z
9Cekwywc3c4tQca/BCTH7q7RDdqPx3yZLCqcGrc6AiBl3QgoOXhEkkaKdl+WfXZkP2pcKILeLiI0
9ZRw1L4rMAaHoNklrw735O4MttO3lvX5oHwoyXQScbLlarLl7kEAtt0Alybir/mMNHkTez0Kg5u/
msP31LzUUJPOoG0ssiY3T7067oO4z8x3VvG4eW+PC1PbZiQM6uCSxLtrcvEC8+OuSL5Lbl6KmQuW
3LxzNy/AzVt9ZQP6ilk4qklLmXrCTfwSPL6pUzMwJJ3w7sjGYTelP8mhJQQiQqhDUykGMGal4tck
466S1IIVQZPzYZg663tBPp7IM+tJtXNOxh3dYnkS7zeqOgZwVj6e2mjff2G4W385jDAPmIhzHy4O
h04vnBq3wgHAESqoeWp7HICq9/KMOhwhbrkDi4ZSz8qERxcqYDiW3hXIf+MzA1edVVncPOtnjbgY
v/zCtWPgL8YfSL11EWQjheBOIqJba8EdICIK/ymPx688gamFsXiLKcUCxNNShoDtu/WlifiLMEle
EOdsFsCaFAY3Vyrge2peaqiJ6lFQlgDbXWj+oXmAKrPyn9mP/wNvi7NrsNYCAA=="

$starter = "
H4sIAAAAAAAEAO1aS27jMAzdDzB3EGYzmxzKR3FRLwx0Fg1gB1Ngdl0G7gdd9jY+ycSxLZH6Uh//
EgdEITOUSD7ySU7ttqraUynkzzNjrD3lSLnLqcyY5vPzB/uN7YrD4dCenhcPdzWS63C7Irf3GR0u
gdkOGpSCiwM11kob3d2LdkODiHWttnyYaxAnJ3delvatC+DE7vd4rP/ZIIIYsV/LRzuvZFZoEDZ3
tDHpOdVW+S67zC+Yhfdw5OkJyDo4VOseJq2e7nKLxjD9eC/2LozPK1WcSxhLDGRt/eJdp61I9ddw
MwBAO14FVFarR0qTbNFYST/KC704EXkliHMxY5l98n//bkEMnItlndVroLGhI/1WDojZyTovL74S
lBf1zItwEbIyyVhh3U3deRruMBMxzn0jRTP2mpgwZsu3kV5M/WbuQz+PYTAmcRFtrGHcbVDOQrbZ
z7eVsE0jac83QheHhDrN+eaOx2tlkrGObWzTz6syC83m/PWmdMcyPKNFrlktNNnp4J0hzvCVHcZa
nm3zYYKNX/tJptVPcpIp60eGakcjoChTlNtsbGDYtu4dczu5VHZBaKKPJC/jOdk1pxevHMNCTVKU
+KR8jE3sYtt4o8Lx9gPTPFUzHOUWqE3iaxzJLE0W/u3qjH8rzAovysLn1srfw8lchGJKVQyg6Itn
Ei3ELuNwRnmFYWrT4Iku47kZlbQokxmbGbXSH1y5k0vqe1fqMk4Dk/gazxkGZRGviZSYKTl6eZyh
KJMZ29i0th9XFCIpTNpll1nEyqTVvE1lfPPJ+LHntfRtrG82znwW2/Vy/1Rw1OUQeP54HR/x+GjQ
9+NCmXvUjAdNjgdiLhuvC34BgzrCr6+DXi8ZlMDmiA3gamjgLOr8VY2sJxuBKAEopQKQpNcipdoX
oKCFMiilgg4dwEa0czEDfI07qwAGJXKCDJS0xoG7oPNtqVl4EQlpTP+rZcrYp+NVHhg2Me4pAg8O
mRozS/jsPgsOlhxtgtbOw6P0iTOmG5whtnXTVg+D1G9t/UkQMKX6UmY1V00z6ptx5cbHxSdYweyd
u9DHIGsi6xC0q9cv7mWrR4FONyagI02RZvUarh8GH239rjG2e9EaqwGbYlA0sTXwuamnlLQHpkvl
gs0r7uqxky+XXN/9PQ9T0PhLaCTsISOgCzH4kpUDrh+YYg3W87nnsSA4Br1mWD+6DmBfygw7VE5a
BcbVwQmyvNQEdi03qL4xTo2ggbYCkggXvCbnMYazDBgkGCeS8P7a1k9DF3RxKvFDDfaeoAKsx1h5
EkoCniGKioBfce+fZVQFXSRgORt6NN6syMPNqF/waUQe71aSO9X7sOZZKSuuBbhMgfzlc0CgU/97
MfZ1vyvyVnpH/S4Y/o0voeZbaPhfzTrYfuh3ae6D7JSf2ar3XtTFte74Zf2eCHXPDX7AnHjPkVwa
0a1ky0RA9ftzTjdfDCRIAqrlfxxB7bHDSwAA"

$ender = "
H4sIAAAAAAAEAO2bS27cQAxE9wHmzllmGyDIAX2SAIYTpC0WWcUmWy24Aa5kip/iEzUejV7f3n59P3
bMtNc7Hb9/aPYvgHSKE8c0MshWGUtkIbN0p/tEx0/CTBm4UwZnXg8nyH4ZZ2VRsjSmw3Rwmhl1kdQy
MlQMfFHGWlkU8b3dAaKJ7SA6IJqRDPHeJupyhNknY58s/F/VaGI7t+0OQmZyVjdnvBxfvztW0sHt29
k7Xsms9slYVaQi/ia7w7o86nfHJX48q30ylhZJin8fHZOpcoUz/rtl7CtSLX4DOjTuuSt5clZbZOxb
cFj8KjpwIwId6Xtm36z2ydhQZCh+AR1Bbei70iFSyD1hTpag0edkrC0yPJFvwXfAKV7nOcsxaIeOL2
/qozbT2cmwcuuqm1YqMtGRdKIqLPJHQaJ7xMeBhg9t+cilzpSWbhAtr5UdnoiF9bEyB4GmY2THCJCw
JhDQI+ed0whcgyQG5SAATk9AnUdgyMs8GQsF28q5BIGExmT2mBEa6kkE/uY9W2AeASm7hEB9eRwC0Q
rKIyBFLnXuQkDPvhQBqjDqP4IqBFZugdF53Ra4HH/IFpC0mUTgTmcwmUmNpXpKEHCmqpdXsgWQLXZO
8wLzhjcgelCfRbaWBRU52u1qefOfBTZxJhEYJbcRABnzgwq7IyNnL1BYnoUAYTs7OwhcB+4D4gRHf5
rsLtGRFATnPc8IvrwdBI4tNP8XDchuv7+UOKNOJ9M1SUeGappOUeTEF9/Ifzi4ycdf7hSvO/3Tts9L
RjoAHZpa8XQqI3fhdtXbdAYO9vXDjZRy5nEjG6G51qRzL448FFJTk5GH6bTi5qsSysY78M453KrGWC
tdX4oSZ8uo3yoPgJYJP4Mbspu3G0FKK25SnVVNKdPJvVYTpyVuK0ncosiUM4+blO5G3EpkmcctiNyF
W3T93LbdLsfPdpusR5lO7pXSQs1KHBhnPkgTKeXS9RE9HPy/BWUVWia/3160gVduNyZI7xh16Zzxrs
MNtRAJjqfzvO1WQv2yMSILtwke7wLcjBZwJcp01PckneNqELstzgGZVEYwxrmukZFBmLAPnM55Znps
oT0Wt8L3D1durdJfypvHrwf9fUkGKX3LI84ZSVJReDzNEsXrC29RPHKeLLyZ8b7Ct1V8KGM948h5sL
iSksKdnFThJJylik9eEMhExkeW+ZtbfEFwkZE/VvyB9gd/X1yctV4AAA=="


Function Get-Base64GZipString {
    param($in)
    $data = [System.Convert]::FromBase64String($in)
    $ms = New-Object System.IO.MemoryStream
    $ms.Write($data, 0, $data.Length)
    $ms.Seek(0, 0) | Out-Null
    $sr = New-Object System.IO.StreamReader(New-Object System.IO.Compression.GZipStream($ms, [System.IO.Compression.CompressionMode]::Decompress))
    return $sr.ReadToEnd()
}

Function Write-Debug {
    param($Message)
    $old = $host.ui.RawUI.CursorPosition
    $host.ui.RawUI.CursorPosition = [System.Management.Automation.Host.Coordinates]::new(200, 1)
    Write-host $Message -NoNewline
    $host.ui.RawUI.CursorPosition = $old
}

Write-Verbose "Reading nyancat frames"
$framedata = Get-Base64GZipString $frames
$decompressedframes = $framedata -split "::"

Write-Verbose "Reading starter"
$vectologo = Get-Base64GZipString $starter

Write-Verbose "Reading ender"
$reminder = Get-Base64GZipString $ender

$globaloffsetX = [System.Math]::Floor(($host.ui.RawUI.WindowSize.Width - 324) / 2)
$globaloffsetY = [System.Math]::Floor(($host.ui.RawUI.WindowSize.Height - 70) / 2) + 1
$vectoslices = $vectologo -split "`n"
Foreach ($slice in $vectoslices) {
    $host.ui.RawUI.CursorPosition = [System.Management.Automation.Host.Coordinates]::new($globaloffsetX, ($vectoslices.indexOf($slice) + $globaloffsetY + 1 ))
    Write-host $slice -NoNewline
}

start-sleep -seconds 2

if ($smol.IsPresent) {
    $offset = 12
}
else {
    $offset = 0
}
$origpos = [System.Management.Automation.Host.Coordinates]::new($globaloffsetX, ($vectoslices.count + $globaloffsetY + 3))
$positionoffset = 200
$currentframe = 0
$i = 0
[console]::CursorVisible = $false
while ($i -lt 300) {
    if ($currentframe -ge 12) {
        $currentframe = 0
    }
    $host.ui.RawUI.CursorPosition = $origpos
    
    if ($currentframe -eq 1) {
        #Fix trash characters on top
        Write-Host ("{0,300}" -f " ") -NoNewline
        Write-Host "`r"
        $host.ui.RawUI.CursorPosition = $origpos
    }
    
    $slices = $decompressedframes[($currentframe + $offset)] -split "`n"
    foreach ($slice in $slices) {
        $host.ui.RawUI.CursorPosition = [System.Management.Automation.Host.Coordinates]::new(($origpos.X + $positionoffset), ($origpos.Y + ($slices.indexOf($slice))))   
        Write-Host $slice -NoNewline
    }

    if ($currentframe -eq 0) {
        #Fix trash characters in the bottom
        $host.ui.RawUI.CursorPosition = [System.Management.Automation.Host.Coordinates]::new(($origpos.X + $positionoffset), ($origpos.Y + 21))
        Write-Host ("{0,300}" -f " ") -NoNewline
    }
    Start-Sleep -Milliseconds 50
    $currentframe++
    $i++
}
[console]::CursorVisible = $true
Clear-Host
Start-Sleep -Milliseconds 200

$reminderslices = $reminder -split "`n"
Foreach ($slice in $reminderslices) {
    $host.ui.RawUI.CursorPosition = [System.Management.Automation.Host.Coordinates]::new($globaloffsetX + 64, ($reminderslices.indexOf($slice) + $globaloffsetY + 8 ))
    Write-host $slice -NoNewline
}

Start-Sleep -Seconds 8
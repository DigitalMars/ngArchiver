#_ win32.mak
# Build win32 version of microemacs
# Needs Digital Mars D compiler to build, available free from:
# http://www.digitalmars.com/d/

DMD=dmd
DEL=del
S=.
O=.
B=.

TARGET=ngarchiver

DFLAGS=-g $(CONF)
LFLAGS=-L/map/co
#DFLAGS=
#LFLAGS=

.d.obj :
	$(DMD) -c $(DFLAGS) $*

SRC= $S\ngarchiver.d $S\date.d $S\datebase.d $S\dateparse.d

OBJ= $O\ngarchiver.obj $O\date.obj $O\datebase.obj $O\dateparse.obj

SOURCE= $(SRC) win32.mak

all: $B\$(TARGET).exe

#################################################

$B\$(TARGET).exe : $(OBJ)
	$(DMD) -of$B\$(TARGET).exe $(OBJ) $(LFLAGS)

$O\ngarchiver.obj: $S\ngarchiver.d
	$(DMD) -c $(DFLAGS) -od$O $S\ngarchiver.d

$O\date.obj: $S\date.d
	$(DMD) -c $(DFLAGS) -od$O $S\date.d

$O\datebase.obj: $S\datebase.d
	$(DMD) -c $(DFLAGS) -od$O $S\datebase.d

$O\dateparse.obj: $S\dateparse.d
	$(DMD) -c $(DFLAGS) -od$O $S\dateparse.d

###################################

clean:
	del $(OBJ) $B\$(TARGET).map


tolf:
	tolf $(SRC)


zip: tolf win32.mak
	$(DEL) ngarchiver.zip
	zip32 ngarchiver $(SOURCE)


git: tolf win32.mak
	\putty\pscp -i c:\.ssh\colossus.ppk $(SRC) walter@mercury:dm/ngArchiver
	\putty\pscp -i c:\.ssh\colossus.ppk win32.mak walter@mercury:dm/ngArchiver/


#######################################################################
#                     SVDPACKC (Ver 1.0) Makefile                     #
#######################################################################
#                                                                     #
#      las2: Single-Vector Lanczos SVD via   A'A    Eigensystems      #
#                                                                     #
#######################################################################
 
CC    =	gcc
CFLAGS=	-O -c 
LIB=	-lm

all:	las2 

las2.o:	las2.h

.c.o:   $*.c 
	${CC} ${CFLAGS} $*.c

las2:	las2.o
	${CC} -o $@ las2.o ${LIB}

clean:
	rm las2.o

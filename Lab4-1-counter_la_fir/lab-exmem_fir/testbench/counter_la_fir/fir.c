#include "fir.h"

void __attribute__ ( ( section ( ".mprjram" ) ) ) initfir() {
	//initial your fir
	for(int i = 0; i < N; i++) {
		inputbuffer[i] = 0;
		outputsignal[i] = 0;
	}
}

int* __attribute__ ( ( section ( ".mprjram" ) ) ) fir(){
	initfir();
	//write down your fir
	int data;
	int coeff;
	for (int i = 0; i < N; i++) {
		inputbuffer[i] = inputsignal[i];
		int result = 0;
		for (int j = 0; j < N; j++) {
			coeff = taps[j];
			data = (j <= i) ? inputbuffer[i - j] : inputbuffer[11 + i - j];
			result += data * coeff;
		}
		outputsignal[i] = result;
	}
	return outputsignal;
}

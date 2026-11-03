//---------------------------------------------------------------------------
#include <stdio.h>
#include "engineUnmixedFan.h"
#include "engineMixedFan.h"
#include "engineACE.h"
#include "engineTurboshaft.h"
#pragma hdrstop

//---------------------------------------------------------------------------

extern EngineACE ACE;
extern EngineMixedFan MixedFan;
extern EngineTurboshaft Turboshaft;

int main(int argc, char* argv[])
{
  int engineType=-1,runMode=-1,inCount=0,isContinue=0;
  int i=0;


//  engineMixedFanCalculate(&MixedFan, 1);     //20221213+
  engineTurboshaftCalculate(&Turboshaft, 1);     //20221213+

    do
    {
      printf("是否继续其余计算？\n"
             " 1 —是\n"
             " 0 —否\n");
      inCount=scanf("%d",&isContinue);
      fflush(stdin);
      if(inCount !=1)
        printf("输入错误：请输入整数！\n");
      if((inCount == 1) && (isContinue < 0|| isContinue >1))
        printf("输入错误：请输入指定范围的整数！\n");
    }while(inCount !=1 || isContinue < 0|| isContinue >1);

  return 0;
}
//---------------------------------------------------------------------------

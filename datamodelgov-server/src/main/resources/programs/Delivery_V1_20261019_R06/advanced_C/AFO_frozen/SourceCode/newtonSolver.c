 /*
 * =============================================================
 * 牛顿法迭代自由变量直至残差变量小于收敛精度
 * =============================================================
 */
#include <stdio.h>		// liukai: 20230214
#include <stdlib.h>		// liukai: 20230214
#include <math.h>
#include "newtonSolver.h"
#include "functions_TMATS.h"
//------------------------------------------------------------------------------


int gaussLinEqu(double *arrGrad,double *bVectorIn,double *xVectorOut,int dime)
{
	  int i = 0,j = 0,k = 0;
  double maxArr = -1;    //存储第i列的绝对值的最大值
  int indexMax = -1;     //指示第i列的绝对值的最大值在哪一行
  double temp=-1;
 
  for(i = 0;i < dime;i++)
  {
    //找出每一列的最大值在哪一行
    maxArr = fabs(arrGrad[i*dime + i]);
    indexMax = i;
    for(j = i + 1;j < dime;j++)
    {
      if(fabs(arrGrad[j*dime + i]) > maxArr)
      {
        maxArr = fabs(arrGrad[j*dime + i]);
        indexMax = j;
      }
    }

    //交换第indexMax行与第i行
    if(indexMax != i)
    {
      for(j = 0;j < dime;j++)
      {
        temp = arrGrad[indexMax*dime + j];
        arrGrad[indexMax*dime + j] = arrGrad[i*dime + j];
        arrGrad[i*dime + j] = temp;
      }
      temp = bVectorIn[indexMax];
      bVectorIn[indexMax] = bVectorIn[i];
      bVectorIn[i] = temp;
    }

    //对梯度矩阵进行三角化
    for(j = i + 1;j < dime;j++)
    {
      temp = arrGrad[j*dime + i];
      for(k = 0;k < dime;k++)
      {
        arrGrad[j*dime + k] -= arrGrad[i*dime + k] * temp * divby(arrGrad[i*dime + i]);
      }
      bVectorIn[j] -= bVectorIn[i] * temp * divby(arrGrad[i*dime + i]);
    }
  }

  //输出三角化后的矩阵arrGrad和数组bVectorIn(仅用于测试该函数)
//  printf("三角化后的arrGrad矩阵为：\n");
//  for(i = 0; i < dime;i++)
//  {
//    for(j = 0; j < dime;j++)
//    {
//      printf("%f\t",arrGrad[i*dime + j]);
//    }
//    printf("\n");
//  }
//  printf("三角化后的bVectorIn数组为：\n");
//  for(i = 0; i < dime;i++)
//  {
//    printf("%f\t",bVectorIn[i]);
//  }
//  printf("\n");

  //根据三角化后的矩阵求解方程组
  for(i = dime - 1;i >=0;i--)
  {
    temp =0;
    for(j = dime -1;j > i;j--)
    {
      temp += xVectorOut[j] * arrGrad[i*dime + j];
    }
    xVectorOut[i] = (bVectorIn[i] - temp) * divby(arrGrad[i*dime + i]);
  }

  //输出方程组的解(仅用于测试该函数)
//  printf("方程组的解为：\n");
//  for(i = 0; i < dime;i++)
//  {
//    printf("%f\t",xVectorOut[i]);
//  }
//  printf("\n");

  return 0;
}
//------------------------------------------------------------------------------
int newtonSolver(int functionModel(double *varIn,double *errOut,int dime),
                 int dime,
                 double *varStart,double *varMin,double *varMax,double *varDelLim,
                 double accuracyReq,
                 double distuFactor,
                 int maxIterations)
{
  int i = 0,j = 0;
  int funTag = 1;          //0表示functionModel计算无误
  int iteCount = 0;        //表示迭代循环次数
  int converge = 0;        //1表示模型收敛
  int needUpjacobi = 1;    //1表示需要更新Jacobi矩阵了
  int jacobiCaling = 0;      //1表示正在计算jacobi矩阵
  int jacobiCollndex = 0;  //表示正在计算jacobi矩阵的哪一列
  int jacobiCalCount = 0;  //表示计算了几次Jacobi矩阵
  int jacobiUseCount = 0;  //表示使用固定的jacobi矩阵更新迭代变量的次数
  double *varIter = (double*)calloc(dime,sizeof(double)); //迭代变量
  double *errIter = (double*)calloc(dime,sizeof(double)); //迭代变量对应的残差
  double *varBest = (double*)calloc(dime,sizeof(double)); //迭代中残差最小的变量
  double *errBest = (double*)calloc(dime,sizeof(double)); //迭代中最小的残差
  double *varDelL = (double*)calloc(dime,sizeof(double)); //无量纲的步长限制
  double *varOld  = (double*)calloc(dime,sizeof(double)); //扰动之前的残差
  double *errOld  = (double*)calloc(dime,sizeof(double)); //扰动之前的残差
  double *varTemp = (double*)calloc(dime,sizeof(double)); //临时存储的迭代变量
  double *errTemp = (double*)calloc(dime,sizeof(double)); //临时存储的残差变量
  double *arrjacobi = (double*)calloc(dime * dime,sizeof(double)); //jacobi矩阵
  double *arrTemp = (double*)calloc(dime * dime,sizeof(double));//临时存储的矩阵
  double minRMSE = -1;     //最小的均方跟残差
  double disturbance = 1;  //扰动
  double temp;             //临时变量

  double k = 1;

  do
  {
    if(iteCount == 0)  //第1步只需将初值赋给迭代变量
    {
      for(i = 0;i < dime;i++)   //迭代变量归一化
      {
        varIter[i] = (varStart[i] - varMin[i]) / (varMax[i] - varMin[i]);
        varDelL[i] =  varDelLim[i] / (varMax[i] - varMin[i]);
      }
      iteCount++;
    }
    else if(needUpjacobi == 1)  //needUpjacobi的初值为1，第2步必需计算jacobi矩阵
    {
      for(i = 0;i < dime;i++)  //varTemp此时存储的是被扰动之前的迭代变量
      {
        varOld[i] = varIter[i];
        errOld[i] = errIter[i];
      }

//      disturbance = (distuFactor * 0.5) +
//                   (distuFactor * 0.5) / (jacobiCalCount + 1.0); //扰动逐渐减小
	  disturbance = distuFactor;		// liukai
	  
      jacobiCollndex = 0;
      temp = varIter[jacobiCollndex] + disturbance;  //扰动第0个变量
      if(temp > 1.0 || temp < 0.0)  //若扰动后的变量超出边界则反向扰动
      {
        varIter[jacobiCollndex] = varIter[jacobiCollndex]  - disturbance;
      }
      else
      {
        varIter[jacobiCollndex] = temp;
      }
      jacobiCaling = 1;    //表示正在计算jacobi矩阵
      jacobiUseCount = 0;  //使用固定的jacobi矩阵更新迭代变量的次数被初始化为0
      needUpjacobi =0;     //撤销需要更新jacobi矩阵的信号
      iteCount++;
    }
    else if(jacobiCaling == 1)
    {
      for(i =0;i < dime;i++)  //更新jacobi矩阵的第jacobiCollndex列
      {
        arrjacobi[i * dime + jacobiCollndex] = (errIter[i] - errOld[i])*
                                             divby(varIter[jacobiCollndex] - varOld[jacobiCollndex]);
      }
      varIter[jacobiCollndex] = varOld[jacobiCollndex];  //将迭代变量还原为扰动之前
      if(jacobiCollndex < (dime - 1))  //jacobi矩阵未计算结束
      {
        jacobiCollndex++;
        temp = varIter[jacobiCollndex] + disturbance;   //扰动第jacobiCollndex个变量
        if(temp > 1.0 || temp < 0.0)  //若扰动后的变量超出边界则反向扰动
        {
          varIter[jacobiCollndex] =  varIter[jacobiCollndex] - disturbance;
        }
        else
        {
          varIter[jacobiCollndex] = temp;
        }
        iteCount++;
      }
      else  //jacobi矩阵计算结束，此时jacobiCollndex == dime - 1
      {
        for(i = 0;i < dime;i++)  //将所有残差还原为扰动之前
        {
          errIter[i] = errOld[i];
        }
        jacobiCaling = 0;  //表示停止计算jacobi矩阵
        //暂时不执行iteCount++操作，马上会根据jacobi矩阵更新迭代变量，在该处执行iteCount++操作
      }
    }

    //使用jacobi矩阵更新迭代变量
    if((jacobiCaling == 0) && (iteCount != 1))
    {
//		if (iteCount == 152 || iteCount == 160)
//		printf("Jacobi:iteCount = %d, jacobiCaling = %d, jacobiCalCount = %d\n", iteCount, jacobiCaling, jacobiCalCount);
      for(i = 0;i < dime;i++)
      {
        errTemp[i] = -errIter[i];
        for(j = 0;j < dime;j++)
        {
           arrTemp[i *dime + j] = arrjacobi[i *dime + j];
//		   if (iteCount == 152 || iteCount == 160)
//		   printf("%f ", arrjacobi[i *dime + j]);
        }
//		if (iteCount == 152 || iteCount == 160)
//		printf("\n");
      }

      gaussLinEqu(arrTemp,errTemp,varTemp,dime);  //求解迭代变量的变化量，并存入varTemp数值
//	  if (jacobiCalCount >= 4)
//		k = (1 * 0.01) + (1 * 0.99) / ((double)jacobiCalCount / 2.0 - 1.0);
	  for (i = 0; i < dime; i++)
	  {
		  while (fabs(varTemp[i]) > fabs(varDelL[i]))  //限制单步迭代的步长
		  {
			  for (j = 0; j < dime; j++)
			  {
				  //      varTemp[i] = ((varTemp[i] >= 0) - (varTemp[i] < 0)) * fabs(varDelL[i]);		// liukai 20300531
				  varTemp[j] = varTemp[j] * 0.9;
			  }
		  }
	  }
      for(i = 0;i < dime;i++)
      {
        varIter[i] = varIter[i] + varTemp[i];
        if(varIter[i] > 1.0)                     //限制迭代变量的上下限
        {
          varIter[i] = 1.0;
        }
        else if(varIter[i] < 0.0)
        {
          varIter[i] = 0.0;
        }
      }
      jacobiUseCount++;
      iteCount++;
    }

    for(i = 0;i < dime;i++) //将归一化后的数据转换为实际值
    {
      varTemp[i] = varIter[i] * (varMax[i] - varMin[i]) + varMin[i];
    }
    funTag = functionModel(varTemp,errIter,dime);  //调用目标函数
	
	// liukai
	if (jacobiCaling == 0)
	{
	/*	printf("iteCount = %d, jacobiCaling = %d\nerror:   ", iteCount, jacobiCaling);
		for (i = 0; i < dime; i++)
		{
			printf("%.8f  ", errIter[i]);
		}
		printf("\n");
		printf("varTemp: ");
		for (i = 0; i < dime; i++)
		{
			printf("%.8f  ", varTemp[i]);
		}
		printf("\n\n");*/
	}

    temp = 0;  //开始计算RMSE
    for(i = 0;i < dime;i++)
    {
      temp += errIter[i] * errIter[i];
    }
    temp = sqrt(temp / (dime * 1.0));  //RMSE计算完毕

    if(temp < accuracyReq) //判断是否收敛
    {
      converge = 1;
    }

    if((iteCount == 1) || (temp < minRMSE))
    {
      minRMSE = temp;
      for(i = 0;i < dime;i++)  //存储迭代中的最优变量和残差
      {
        varBest[i] = varIter[i];
        errBest[i] = errIter[i];
      }
    }

    //使用jacobi矩阵更新完迭代变化后，判断是否发出需要更新jacobi矩阵的信号
    if((jacobiCaling == 0) && (iteCount != 1))
    {
    //  if(temp > minRMSE)  //如果迭代开始发散
	  if (1)  //如果迭代开始发散
      {
        needUpjacobi = 1;  //发出需要更新jacobi矩阵的信号
        jacobiCalCount++;    //增加计算jacobi矩阵的次数
        if(jacobiUseCount != 1)
        {
          for(i = 0;i < dime;i++)  //将存储的最优变量和残差赋回当前的迭代变量和残差
          {
            varIter[i] = varBest[i];
            errIter[i] = errBest[i];
          }
        }
      }
      else if(jacobiUseCount == (dime + 1))  //使用固定的jacobi矩阵更新迭代变量的次数超过了矩阵的维度
      {
        needUpjacobi = 1;  //发出需要更新jacobi矩阵的信号
        jacobiCalCount++;    //增加计算jacobi矩阵的次数
      }
    }
  }while((converge == 0)&&(jacobiCalCount < maxIterations) && (funTag ==0));

  for(i = 0;i < dime;i++) //将归一化后的数据转换为实际值，并输出至初值
  {
    varStart[i] = varIter[i] * (varMax[i] - varMin[i]) + varMin[i];
  }

  free(varIter);  //释放内存
  free(errIter);
  free(varBest);
  free(errBest);
  free(varDelL);
  free(varOld);
  free(errOld);
  free(varTemp);
  free(errTemp);
  free(arrjacobi);
  free(arrTemp);

  if(converge == 1)
  {
    return 0;
  }
  else if(jacobiCalCount == maxIterations)
  {
    return 1;
  }
  else if(funTag ==0)
  {
    return 2;
  }
  else
  {
    return 3;
  }
}
//------------------------------------------------------------------------------
